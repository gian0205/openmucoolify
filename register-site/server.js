// Servidor mínimo de cadastro para OpenMU (MU Online).
// Insere direto na tabela data."Account" usando hash BCrypt compatível com BCrypt.Net (.NET).
//
// Variáveis de ambiente:
//   PORT             — porta HTTP (default 3000)
//   PGHOST           — host do Postgres (default "database")
//   PGPORT           — porta (default 5432)
//   PGDATABASE       — DB (default "openmu")
//   PGUSER           — user (default "postgres")
//   PGPASSWORD       — senha (obrigatório)
//   BCRYPT_ROUNDS    — workfactor (default 11, igual default do BCrypt.Net-Next)
//   RATE_WINDOW_MS   — janela de rate limit (default 600000 = 10 min)
//   RATE_MAX         — máximo de cadastros por IP por janela (default 3)
//   TRUST_PROXY      — "true" se atrás de Traefik/Coolify (default "true")
//   DOWNLOADS_DIR    — pasta com os zips do client pra hospedar (default /app/downloads)
//   DOWNLOAD_RATE_MAX — máximo de downloads por IP por janela (default 30)

import express from 'express';
import rateLimit from 'express-rate-limit';
import bcrypt from 'bcryptjs';
import pg from 'pg';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PORT = Number(process.env.PORT || 3000);
const BCRYPT_ROUNDS = Number(process.env.BCRYPT_ROUNDS || 11);
const RATE_WINDOW_MS = Number(process.env.RATE_WINDOW_MS || 10 * 60 * 1000);
const RATE_MAX = Number(process.env.RATE_MAX || 3);
const TRUST_PROXY = (process.env.TRUST_PROXY ?? 'true') !== 'false';
const DOWNLOADS_DIR = process.env.DOWNLOADS_DIR || '/app/downloads';
const DOWNLOAD_RATE_MAX = Number(process.env.DOWNLOAD_RATE_MAX || 30);

const pool = new pg.Pool({
  host: process.env.PGHOST || 'database',
  port: Number(process.env.PGPORT || 5432),
  database: process.env.PGDATABASE || 'openmu',
  user: process.env.PGUSER || 'postgres',
  password: process.env.PGPASSWORD,
  max: 5,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
});

pool.on('error', (err) => console.error('[pg pool]', err));

const app = express();
if (TRUST_PROXY) app.set('trust proxy', 1);
app.use(express.json({ limit: '4kb' }));
app.use(express.static(path.join(__dirname, 'public'), {
  maxAge: '1h',
  setHeaders: (res, p) => {
    if (p.endsWith('.html')) res.setHeader('Cache-Control', 'no-store');
  },
}));

// ── Validação ────────────────────────────────────────────────────────────
// LoginName é varchar(10) NOT NULL no schema do OpenMU. Restringimos a
// alfanuméricos + underscore, 4–10 chars, pra bater com os clients de MU.
const RE_LOGIN = /^[A-Za-z0-9_]{4,10}$/;
const RE_EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function validate({ user, email, password }) {
  if (!user || typeof user !== 'string' || !RE_LOGIN.test(user)) {
    return 'Login inválido. Use 4–10 caracteres (letras, números ou _).';
  }
  if (!email || typeof email !== 'string' || email.length > 100 || !RE_EMAIL.test(email)) {
    return 'E-mail inválido.';
  }
  if (!password || typeof password !== 'string' || password.length < 8 || password.length > 64) {
    return 'Senha precisa ter entre 8 e 64 caracteres.';
  }
  return null;
}

// ── Health ───────────────────────────────────────────────────────────────
app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true });
  } catch (e) {
    res.status(503).json({ ok: false });
  }
});

// ── Stats (para o painel "Status do Reino") ──────────────────────────────
app.get('/api/stats', async (_req, res) => {
  try {
    const r = await pool.query('SELECT COUNT(*)::int AS n FROM data."Account"');
    res.json({
      ok: true,
      accountsCreated: r.rows[0]?.n ?? 0,
      status: 'online',
    });
  } catch {
    res.json({ ok: false, accountsCreated: 0, status: 'unknown' });
  }
});

// ── Downloads ────────────────────────────────────────────────────────────
// Serve zips do client a partir de DOWNLOADS_DIR (bind-mount no host).
// O usuário sobe o zip via SCP pra esse diretório uma única vez.

// Cache em memória do SHA-256 (recalculado quando o arquivo muda)
const sha256Cache = new Map(); // path -> { mtimeMs, sha }

function sha256Of(filePath, sizeBytes, mtimeMs) {
  const cached = sha256Cache.get(filePath);
  if (cached && cached.mtimeMs === mtimeMs) return Promise.resolve(cached.sha);
  return new Promise((resolve, reject) => {
    const h = crypto.createHash('sha256');
    fs.createReadStream(filePath)
      .on('data', c => h.update(c))
      .on('end', () => {
        const sha = h.digest('hex');
        sha256Cache.set(filePath, { mtimeMs, sha });
        resolve(sha);
      })
      .on('error', reject);
  });
}

// Encontra o zip mais recente, valida que tá dentro de DOWNLOADS_DIR
function findLatestClientZip() {
  if (!fs.existsSync(DOWNLOADS_DIR)) return null;
  const candidates = fs.readdirSync(DOWNLOADS_DIR)
    .filter(n => /^MuPorcaria-Client-.*\.zip$/i.test(n))
    .map(n => {
      const full = path.join(DOWNLOADS_DIR, n);
      try {
        const st = fs.statSync(full);
        return st.isFile() ? { name: n, full, size: st.size, mtimeMs: st.mtimeMs } : null;
      } catch { return null; }
    })
    .filter(Boolean)
    .sort((a, b) => b.mtimeMs - a.mtimeMs);
  return candidates[0] ?? null;
}

app.get('/api/latest-client', async (_req, res) => {
  const z = findLatestClientZip();
  if (!z) return res.json({ ok: false, error: 'no client uploaded yet' });
  try {
    const sha = await sha256Of(z.full, z.size, z.mtimeMs);
    res.json({
      ok: true,
      filename: z.name,
      url: `/download/${encodeURIComponent(z.name)}`,
      sizeBytes: z.size,
      sizeHuman: humanBytes(z.size),
      sha256: sha,
      uploadedAt: new Date(z.mtimeMs).toISOString(),
    });
  } catch (e) {
    console.error('[sha256]', e);
    res.json({ ok: false, error: 'failed to hash file' });
  }
});

function humanBytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1048576) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1073741824) return `${(n / 1048576).toFixed(1)} MB`;
  return `${(n / 1073741824).toFixed(2)} GB`;
}

// Rate limit do download — generoso, mas evita scraping idiota
const downloadLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,            // 1h
  max: DOWNLOAD_RATE_MAX,              // 30 downloads/h por IP
  standardHeaders: true,
  legacyHeaders: false,
  message: 'Too many downloads. Wait a bit.',
});

// Servir os zips com Content-Disposition pra forçar download e nome bonito
if (fs.existsSync(DOWNLOADS_DIR)) {
  app.use('/download', downloadLimiter, express.static(DOWNLOADS_DIR, {
    index: false,                      // sem listagem (privacidade)
    dotfiles: 'ignore',
    fallthrough: false,                // 404 limpo se arquivo não existe
    maxAge: '1d',
    setHeaders: (res, p) => {
      if (p.toLowerCase().endsWith('.zip')) {
        res.setHeader('Content-Disposition', `attachment; filename="${path.basename(p)}"`);
        res.setHeader('Content-Type', 'application/zip');
      }
    },
  }));
} else {
  console.warn(`[downloads] ${DOWNLOADS_DIR} não existe — /download/* desativado.`);
}

// ── Registro ─────────────────────────────────────────────────────────────
const registerLimiter = rateLimit({
  windowMs: RATE_WINDOW_MS,
  max: RATE_MAX,
  standardHeaders: true,
  legacyHeaders: false,
  message: { ok: false, error: 'Muitas tentativas. Aguarde alguns minutos e tente de novo.' },
});

app.post('/api/register', registerLimiter, async (req, res) => {
  const { user, email, password } = req.body ?? {};
  const err = validate({ user, email, password });
  if (err) return res.status(400).json({ ok: false, error: err });

  // SecurityCode default — o jogador pode trocar depois pelo painel admin
  // ou em cooperação com o staff. Mantemos um número aleatório em vez de
  // string vazia pra não dar conflito caso algum plug-in valide o tamanho.
  const securityCode = String(crypto.randomInt(1000, 9999));

  try {
    const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

    const insert = `
      INSERT INTO data."Account" (
        "Id", "LoginName", "PasswordHash", "SecurityCode", "EMail",
        "RegistrationDate", "State", "TimeZone", "VaultPassword", "IsVaultExtended"
      ) VALUES (
        gen_random_uuid(), $1, $2, $3, $4,
        now(), 0, 0, '', false
      )
    `;
    await pool.query(insert, [user, passwordHash, securityCode, email]);

    res.json({ ok: true, login: user });
  } catch (e) {
    // Postgres unique_violation = 23505. O índice único do LoginName cobre isso.
    if (e?.code === '23505') {
      return res.status(409).json({ ok: false, error: 'Esse nome de login já existe.' });
    }
    // Se o schema/tabela ainda não foi criado pelo OpenMU
    if (e?.code === '42P01') {
      return res.status(503).json({
        ok: false,
        error: 'O servidor de jogo ainda está inicializando o banco. Tenta de novo em alguns segundos.',
      });
    }
    console.error('[register]', e);
    res.status(500).json({ ok: false, error: 'Erro interno. Tenta de novo daqui a pouco.' });
  }
});

app.listen(PORT, () => {
  console.log(`[register] ouvindo em http://0.0.0.0:${PORT}`);
});

const shutdown = async (sig) => {
  console.log(`[register] ${sig} recebido, encerrando...`);
  await pool.end().catch(() => {});
  process.exit(0);
};
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

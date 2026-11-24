#!/bin/bash
# ==========================================
# ☁️ ASUPAN VGK v8.0 - ADMIN APPROVAL
# Paywall • Manual QRIS • Blur Video • FAQ
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

read -p "👉 Masukkan Domain Web (contoh: vgk.domain.com): " DOMAIN
[[ -z "$DOMAIN" ]] && { echo -e "${RED}❌ Domain tidak boleh kosong!${NC}"; exit 1; }
read -p "👉 Email SSL: " EMAIL
[[ -z "$EMAIL" ]] && EMAIL="admin@$DOMAIN"

WEB_ROOT="/var/www/$DOMAIN"
DB_NAME="asupan_db"
DB_USER="asupan_user"
DB_PASS=$(openssl rand -hex 12)
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

# ==========================================
# 1. INSTALL DEPENDENCY
# ==========================================
echo -e "${CYAN}[1/6] Install Nginx, PHP, MariaDB...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -qq
apt install -y nginx php8.3-fpm php8.3-mysql php8.3-mbstring php8.3-curl php8.3-xml php8.3-zip php8.3-gd php8.3-sodium mariadb-server mariadb-client certbot python3-certbot-nginx >/dev/null 2>&1
systemctl enable --now nginx php8.3-fpm mariadb >/dev/null 2>&1

# Limit Upload PHP 3GB
sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 3000M/' /etc/php/8.3/fpm/php.ini
sed -i 's/post_max_size = 8M/post_max_size = 3000M/' /etc/php/8.3/fpm/php.ini
sed -i 's/max_execution_time = 30/max_execution_time = 300/' /etc/php/8.3/fpm/php.ini
systemctl restart php8.3-fpm

# ==========================================
# 2. SETUP DATABASE
# ==========================================
echo -e "${CYAN}[2/6] Setup Database...${NC}"
mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;"
mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

mysql "$DB_NAME" << SQLEOF
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    role ENUM('admin','user') DEFAULT 'user',
    plan ENUM('free','premium') DEFAULT 'free',
    plan_expires DATETIME NULL,
    is_banned TINYINT(1) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- Admin Default (Pass: Rend11#)
INSERT INTO users (username, password, role, plan) VALUES ('admin', 'Rend11#', 'admin', 'premium');

CREATE TABLE videos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(100),
    filename VARCHAR(100),
    is_locked TINYINT(1) DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE settings (
    id INT PRIMARY KEY,
    site_name VARCHAR(100) DEFAULT 'Asupan VGK',
    maintenance INT DEFAULT 0,
    qris_manual VARCHAR(255) DEFAULT ''
);
INSERT INTO settings (id) VALUES (1);

CREATE TABLE transactions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    amount INT,
    proof_image VARCHAR(255),
    status ENUM('pending','success','failed') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE activity_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    action VARCHAR(100),
    ip_address VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQLEOF
echo -e "${GREEN}  ✅ Database Siap${NC}"

# ==========================================
# 3. BIKIN FILE WEB (UI DARK PREMIUM)
# ==========================================
echo -e "${CYAN}[3/6] Generate File Web (Mobile First)...${NC}"
rm -rf "$WEB_ROOT"
mkdir -p "$WEB_ROOT"/{assets,uploads/videos,admin}

# --- CONFIG.PHP ---
cat > "$WEB_ROOT/config.php" << PHPEOF
<?php
session_start();
define('DB_HOST', '127.0.0.1');
define('DB_NAME', '$DB_NAME');
define('DB_USER', '$DB_USER');
define('DB_PASS', '$DB_PASS');
try {
    \$pdo = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
} catch (PDOException \$e) { die("DB Error"); }

function isLoggedIn() { return isset(\$_SESSION['user_id']); }
function isAdmin() { return isLoggedIn() && \$_SESSION['role'] === 'admin'; }
function requireLogin() { if(!isLoggedIn()) { header('Location: login.php'); exit; } }
function getSettings(\$pdo) { return \$pdo->query("SELECT * FROM settings WHERE id=1")->fetch(); }

function logActivity(\$pdo, \$action) {
    \$uid = \$_SESSION['user_id'] ?? 0;
    \$ip = \$_SERVER['REMOTE_ADDR'] ?? 'Unknown';
    \$pdo->prepare("INSERT INTO activity_logs (user_id, action, ip_address) VALUES (?,?,?)")->execute([\$uid, \$action, \$ip]);
}

function canWatchVideo(\$pdo, \$user_id, \$video_id) {
    if(!\$user_id) return false;
    \$u = \$pdo->query("SELECT * FROM users WHERE id=\$user_id")->fetch();
    if(\$u['role'] == 'admin') return true;
    if(\$u['plan'] == 'premium' && \$u['plan_expires'] && strtotime(\$u['plan_expires']) > time()) return true;
    return false;
}
PHPEOF

# --- STYLE.CSS ---
cat > "$WEB_ROOT/assets/style.css" << 'CSSEOF'
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');
@import url('https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css');
:root { --bg: #09090d; --card: #14141b; --primary: #6366f1; --gold: #facc15; --success: #10b981; --danger: #ef4444; --text: #fff; --muted: #94a3b8; --border: #26262f; }
* { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Inter', sans-serif; }
body { background: var(--bg); color: var(--text); min-height: 100vh; -webkit-font-smoothing: antialiased; }
a { text-decoration: none; color: inherit; }
.container { max-width: 1000px; margin: 0 auto; padding: 20px; }

/* NAVBAR */
.navbar { display: flex; justify-content: space-between; align-items: center; padding: 15px 20px; background: rgba(9,9,13,0.9); backdrop-filter: blur(10px); border-bottom: 1px solid var(--border); position: sticky; top: 0; z-index: 100; }
.logo { font-size: 1.3em; font-weight: 800; color: var(--gold); display: flex; align-items: center; gap: 8px; }
.btn { padding: 10px 20px; border-radius: 8px; font-weight: 700; border: none; cursor: pointer; display: inline-flex; align-items: center; gap: 8px; transition: 0.3s; font-size: 0.9em; }
.btn-primary { background: var(--primary); color: white; }
.btn-gold { background: var(--gold); color: #000; }
.btn-danger { background: rgba(239,68,68,0.1); color: var(--danger); border: 1px solid var(--danger); }

/* HERO */
.hero { text-align: center; padding: 60px 20px; }
.hero h1 { font-size: 3em; font-weight: 800; margin-bottom: 20px; line-height: 1.1; }
.hero h1 span { color: var(--gold); }
.hero p { color: var(--muted); font-size: 1.2em; margin-bottom: 30px; }

/* STATS */
.stats { display: flex; justify-content: center; gap: 40px; padding: 30px 20px; background: var(--card); border-top: 1px solid var(--border); border-bottom: 1px solid var(--border); margin-bottom: 40px; }
.stat-item { text-align: center; }
.stat-item h3 { font-size: 2em; color: var(--gold); font-weight: 800; }
.stat-item p { color: var(--muted); font-size: 0.9em; text-transform: uppercase; }

/* FAQ */
.faq-item { background: var(--card); border: 1px solid var(--border); border-radius: 12px; margin-bottom: 10px; overflow: hidden; }
.faq-q { padding: 16px 20px; cursor: pointer; font-weight: 600; display: flex; justify-content: space-between; align-items: center; }
.faq-q:after { content: '\f067'; font-family: 'Font Awesome 5 Free'; font-weight: 900; color: var(--gold); }
.faq-item.open .faq-q:after { content: '\f068'; }
.faq-a { padding: 0 20px; max-height: 0; overflow: hidden; color: var(--muted); transition: 0.3s; }
.faq-item.open .faq-a { max-height: 200px; padding-bottom: 16px; }

/* TESTIMONI */
.testimonials { padding: 40px 20px; text-align: center; }
.testi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 20px; margin-top: 30px; }
.testi-card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 25px; text-align: left; }
.stars { color: var(--gold); margin-bottom: 10px; }
.testi-card p { font-style: italic; color: var(--muted); margin-bottom: 15px; font-size: 0.95em; }
.testi-user { display: flex; align-items: center; gap: 10px; }
.avatar { width: 40px; height: 40px; border-radius: 50%; background: var(--primary); display: flex; align-items: center; justify-content: center; font-weight: 800; }

/* VIDEO GRID */
.video-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 20px; }
.video-card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; overflow: hidden; transition: 0.3s; position: relative; }
.video-thumb { position: relative; aspect-ratio: 16/9; background: #000; overflow: hidden; }
.video-thumb video { width: 100%; height: 100%; object-fit: cover; pointer-events: none; filter: blur(10px); }
.video-thumb.unlocked video { filter: none; pointer-events: auto; }
.lock-overlay { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; background: rgba(0,0,0,0.5); z-index: 2; }
.lock-overlay i { font-size: 2.5em; color: var(--gold); margin-bottom: 10px; }
.video-info { padding: 15px; }

/* LOGIN FORM (MOBILE FIRST) */
.login-box { max-width: 400px; margin: 80px auto; padding: 30px; }
.login-box input { width: 100%; padding: 12px; margin-bottom: 15px; border-radius: 8px; border: 1px solid var(--border); background: #0f172a; color: #fff; }
.login-box button { width: 100%; padding: 12px; border-radius: 8px; border: none; background: var(--primary); color: white; font-weight: 700; }

/* ADMIN SIDEBAR */
.admin-layout { display: flex; min-height: 100vh; }
.sidebar { width: 260px; background: var(--card); border-right: 1px solid var(--border); padding: 20px; position: fixed; height: 100%; overflow-y: auto; }
.sidebar a { display: flex; align-items: center; gap: 12px; padding: 12px; color: var(--muted); border-radius: 8px; margin-bottom: 5px; font-weight: 600; }
.sidebar a:hover, .sidebar a.active { background: rgba(99,102,241,0.1); color: var(--primary); }
.admin-content { margin-left: 260px; padding: 30px; flex: 1; }

@media (max-width: 768px) {
    .hero h1 { font-size: 2em; }
    .sidebar { transform: translateX(-100%); transition: 0.3s; z-index: 1000; }
    .sidebar.open { transform: translateX(0); }
    .admin-content { margin-left: 0; }
    .mobile-toggle { display: block; position: fixed; top: 15px; left: 15px; z-index: 1001; background: var(--primary); color: white; padding: 10px; border-radius: 8px; border: none; }
    .stats { flex-direction: column; gap: 20px; }
}

/* ANTI SCREENSHOT */
body.screen-protect { background: #000 !important; }
body.screen-protect * { visibility: hidden !important; }
body.screen-protect::after { content: 'SCREENSHOT DETECTED'; visibility: visible; color: #ef4444; font-size: 2em; font-weight: 800; position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%); z-index: 9999; }
CSSEOF

# --- INDEX.PHP (LANDING) ---
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php require 'config.php'; $set = getSettings($pdo); $videos = $pdo->query("SELECT * FROM videos ORDER BY id DESC LIMIT 6")->fetchAll(); $uid = $_SESSION['user_id'] ?? 0; ?>
<!DOCTYPE html>
<html lang="id">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title><?= $set['site_name'] ?> - Premium Content</title><link rel="stylesheet" href="assets/style.css"></head>
<body>
    <nav class="navbar">
        <a href="index.php" class="logo"><i class="fas fa-fire"></i> <?= $set['site_name'] ?></a>
        <div>
            <?php if(isLoggedIn()): ?>
                <a href="<?= isAdmin() ? 'admin/index.php' : 'dashboard.php' ?>" class="btn btn-primary"><i class="fas fa-user"></i> Dashboard</a>
            <?php else: ?>
                <a href="login.php" class="btn btn-primary">Login</a>
                <a href="register.php" class="btn btn-gold">Daftar</a>
            <?php endif; ?>
        </div>
    </nav>

    <div class="hero">
        <h1>Nonton Video <span>Eksklusif</span> Tanpa Batas!</h1>
        <p>Akses ribuan video premium dengan kualitas terbaik. Update setiap hari tanpa henti.</p>
        <a href="pricing.php" class="btn btn-gold" style="padding:15px 30px; font-size:1.1em;"><i class="fas fa-crown"></i> Beli Premium Sekarang</a>
    </div>

    <div class="stats">
        <div class="stat-item"><h3>12.5K+</h3><p>Member Aktif</p></div>
        <div class="stat-item"><h3>50K+</h3><p>Video Premium</p></div>
        <div class="stat-item"><h3>4.9/5</h3><p>Rating Pengguna</p></div>
    </div>

    <div class="testimonials">
        <h2>Kata Mereka</h2>
        <div class="testi-grid">
            <div class="testi-card"><div class="stars">★★★★★</div><p>"Gila sih ini, video-nya lengkap banget. Worth it beli paket Premium!"</p><div class="testi-user"><div class="avatar">A</div><b>Andi</b></div></div>
            <div class="testi-card"><div class="stars">★★★★★</div><p>"Anti screenshot-nya keren, jadi aman. Adminnya fast respon juga."</p><div class="testi-user"><div class="avatar">R</div><b>Rina</b></div></div>
        </div>
    </div>

    <div class="container" style="margin-bottom:60px;">
        <h2 style="text-align:center; margin-bottom:30px;">Preview Video</h2>
        <div class="video-grid">
            <?php foreach($videos as $v): $canWatch = canWatchVideo($pdo, $uid, $v['id']); ?>
            <div class="video-card">
                <div class="video-thumb <?= $canWatch ? 'unlocked' : '' ?>">
                    <video src="uploads/videos/<?= $v['filename'] ?>" preload="metadata" muted playsinline controls="<?= $canWatch ? 'true' : 'false' ?>"></video>
                    <?php if(!$canWatch): ?>
                    <div class="lock-overlay"><i class="fas fa-lock"></i><h3>Wajib Premium</h3><a href="pricing.php" class="btn btn-gold" style="margin-top:10px;">Beli Akses</a></div>
                    <?php endif; ?>
                </div>
                <div class="video-info"><h4><?= htmlspecialchars($v['title']) ?></h4></div>
            </div>
            <?php endforeach; ?>
        </div>
    </div>

    <div class="container">
        <h2 style="text-align:center; margin-bottom:20px;">FAQ</h2>
        <div class="faq-item"><div class="faq-q" onclick="this.parentElement.classList.toggle('open')">Apakah video update setiap hari?</div><div class="faq-a">Ya, kami update video premium setiap hari tanpa henti.</div></div>
        <div class="faq-item"><div class="faq-q" onclick="this.parentElement.classList.toggle('open')">Bagaimana cara pembayarannya?</div><div class="faq-a">Pembayaran dilakukan via QRIS. Kamu wajib kirim bukti transfer agar akun di-approve admin.</div></div>
    </div>
</body>
</html>
PHPEOF

# --- LOGIN & REGISTER ---
cat > "$WEB_ROOT/login.php" << 'PHPEOF'
<?php require 'config.php';
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $u = $_POST['username']; $p = $_POST['password'];
    $stmt = $pdo->prepare("SELECT * FROM users WHERE username=?"); $stmt->execute([$u]); $user = $stmt->fetch();
    if ($user && ($p === $user['password'])) {
        if($user['is_banned']) { $err = "Akun Anda diblokir!"; }
        else {
            $_SESSION['user_id'] = $user['id']; $_SESSION['role'] = $user['role'];
            logActivity($pdo, "Login ke sistem");
            header('Location: ' . ($user['role'] === 'admin' ? 'admin/index.php' : 'dashboard.php')); exit;
        }
    } else { $err = "Username/Password salah!"; }
}
?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><title>Login</title><link rel="stylesheet" href="assets/style.css"></head>
<body><div class="login-box card">
    <h2 style="text-align:center; margin-bottom:20px;"><i class="fas fa-lock"></i> Login</h2>
    <?php if(isset($err)) echo "<p style='color:var(--danger); text-align:center; margin-bottom:15px;'>$err</p>"; ?>
    <form method="POST"><input type="text" name="username" placeholder="Username" required><input type="password" name="password" placeholder="Password" required><button>Masuk</button></form>
    <p style="text-align:center; margin-top:15px; font-size:0.9em; color:var(--muted);">Belum punya akun? <a href="register.php" style="color:var(--primary);">Daftar</a></p>
</div></body></html>
PHPEOF

cat > "$WEB_ROOT/register.php" << 'PHPEOF'
<?php require 'config.php';
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $u = $_POST['username']; $p = $_POST['password'];
    try { $stmt = $pdo->prepare("INSERT INTO users (username, password) VALUES (?,?)"); $stmt->execute([$u, $p]); header('Location: login.php'); exit; } catch(Exception $e) { $err = "Username sudah ada!"; }
}
?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><title>Daftar</title><link rel="stylesheet" href="assets/style.css"></head>
<body><div class="login-box card">
    <h2 style="text-align:center; margin-bottom:20px;"><i class="fas fa-user-plus"></i> Daftar</h2>
    <?php if(isset($err)) echo "<p style='color:var(--danger); text-align:center; margin-bottom:15px;'>$err</p>"; ?>
    <form method="POST"><input type="text" name="username" placeholder="Username" required><input type="password" name="password" placeholder="Password" required><button style="background:var(--gold); color:#000;">Daftar</button></form>
    <p style="text-align:center; margin-top:15px; font-size:0.9em; color:var(--muted);">Sudah punya akun? <a href="login.php" style="color:var(--primary);">Login</a></p>
</div></body></html>
PHPEOF

# --- DASHBOARD USER & PRICING ---
cat > "$WEB_ROOT/dashboard.php" << 'PHPEOF'
<?php require 'config.php'; requireLogin();
$stmt = $pdo->prepare("SELECT * FROM users WHERE id=?"); $stmt->execute([$_SESSION['user_id']]); $me = $stmt->fetch();
$videos = $pdo->query("SELECT * FROM videos ORDER BY id DESC")->fetchAll();
?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Dashboard</title><link rel="stylesheet" href="assets/style.css"></head>
<body>
    <nav class="navbar"><a href="dashboard.php" class="logo"><i class="fas fa-fire"></i> Asupan VGK</a><a href="logout.php" class="btn btn-danger"><i class="fas fa-sign-out-alt"></i> Logout</a></nav>
    <div class="container">
        <div class="card" style="background:linear-gradient(135deg, rgba(99,102,241,0.2), transparent);">
            <h2 style="margin-bottom:5px;">Halo, <?= htmlspecialchars($me['username']) ?>!</h2>
            <p style="color:var(--muted); margin-bottom:15px;">Status: <b style="color:var(--gold);"><?= strtoupper($me['plan']) ?></b></p>
            <?php if($me['plan'] == 'free'): ?><a href="pricing.php" class="btn btn-gold"><i class="fas fa-crown"></i> Beli Premium (25rb)</a><?php endif; ?>
        </div>
        <h2 style="margin:20px 0;">Video Premium</h2>
        <div class="video-grid">
            <?php foreach($videos as $v): $canWatch = canWatchVideo($pdo, $me['id'], $v['id']); ?>
            <div class="video-card">
                <div class="video-thumb <?= $canWatch ? 'unlocked' : '' ?>">
                    <video src="uploads/videos/<?= $v['filename'] ?>" preload="metadata" muted playsinline controls="<?= $canWatch ? 'true' : 'false' ?>"></video>
                    <?php if(!$canWatch): ?>
                    <div class="lock-overlay"><i class="fas fa-lock"></i><h3>Wajib Premium</h3><a href="pricing.php" class="btn btn-gold" style="margin-top:10px;">Beli Akses</a></div>
                    <?php endif; ?>
                </div>
                <div class="video-info"><h4><?= htmlspecialchars($v['title']) ?></h4></div>
            </div>
            <?php endforeach; ?>
        </div>
    </div>
</body></html>
PHPEOF

cat > "$WEB_ROOT/pricing.php" << 'PHPEOF'
<?php require 'config.php'; requireLogin(); $set = getSettings($pdo);
$stmt = $pdo->prepare("SELECT * FROM users WHERE id=?"); $stmt->execute([$_SESSION['user_id']]); $me = $stmt->fetch();
$msg = '';
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_FILES['proof'])) {
    $fn = 'proof_' . time() . '_' . $_FILES['proof']['name'];
    if (move_uploaded_file($_FILES['proof']['tmp_name'], 'uploads/' . $fn)) {
        $pdo->prepare("INSERT INTO transactions (user_id, amount, proof_image) VALUES (?, 25000, ?)")->execute([$me['id'], $fn]);
        logActivity($pdo, "Upload bukti bayar");
        $msg = "Bukti transfer berhasil dikirim! Tunggu approve admin.";
    }
}
?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><title>Pricing</title><link rel="stylesheet" href="assets/style.css"></head>
<body>
    <nav class="navbar"><a href="dashboard.php" class="logo"><i class="fas fa-arrow-left"></i> Kembali</a></nav>
    <div class="container" style="max-width:500px;">
        <?php if($msg): ?><div style="background:rgba(16,185,129,0.2); color:var(--success); padding:15px; border-radius:10px; margin-bottom:20px;"><?= $msg ?></div><?php endif; ?>
        <div class="card" style="text-align:center;">
            <h1 style="color:var(--gold);">Premium (25rb)</h1>
            <p style="color:var(--muted); margin-bottom:20px;">Akses Semua Video</p>
            <?php if($set['qris_manual']): ?>
            <img src="<?= $set['qris_manual'] ?>" style="width:100%; max-width:300px; border-radius:10px; margin-bottom:20px;">
            <?php else: ?>
            <p style="color:var(--danger); margin-bottom:20px;">QRIS belum di-set Admin!</p>
            <?php endif; ?>
            <form method="POST" enctype="multipart/form-data">
                <p style="margin-bottom:10px;">Kirim Bukti Transfer:</p>
                <input type="file" name="proof" required style="margin-bottom:15px;">
                <button class="btn btn-gold" style="width:100%;">Kirim Bukti</button>
            </form>
        </div>
    </div>
</body></html>
PHPEOF

cat > "$WEB_ROOT/logout.php" << 'PHPEOF'
<?php session_start(); session_destroy(); header('Location: login.php'); exit;
PHPEOF

# ==========================================
# 4. ADMIN PANEL
# ==========================================
cat > "$WEB_ROOT/admin/index.php" << 'PHPEOF'
<?php require '../config.php'; if(!isAdmin()) { header('Location: ../login.php'); exit; }
$set = getSettings($pdo);
$totalUser = $pdo->query("SELECT COUNT(*) FROM users WHERE role='user'")->fetchColumn();
$totalVid = $pdo->query("SELECT COUNT(*) FROM videos")->fetchColumn();
$pending = $pdo->query("SELECT COUNT(*) FROM transactions WHERE status='pending'")->fetchColumn();
?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><title>Admin Panel</title><link rel="stylesheet" href="../assets/style.css"></head>
<body>
    <button class="mobile-toggle" onclick="document.querySelector('.sidebar').classList.toggle('open')"><i class="fas fa-bars"></i></button>
    <div class="admin-layout">
        <div class="sidebar">
            <h2 style="color:var(--gold); margin-bottom:20px;"><i class="fas fa-shield-alt"></i> Admin VGK</h2>
            <a href="index.php" class="active"><i class="fas fa-home"></i> Dashboard</a>
            <a href="videos.php"><i class="fas fa-video"></i> Video Manager</a>
            <a href="users.php"><i class="fas fa-users"></i> Users</a>
            <a href="finance.php"><i class="fas fa-money-bill-wave"></i> Keuangan (Pending: <?= $pending ?>)</a>
            <a href="console.php"><i class="fas fa-terminal"></i> Console Log</a>
            <a href="settings.php"><i class="fas fa-cog"></i> Settings</a>
            <a href="../logout.php" style="color:var(--danger); margin-top:20px;"><i class="fas fa-sign-out-alt"></i> Logout</a>
        </div>
        <div class="admin-content">
            <h1 style="margin-bottom:20px;">Overview</h1>
            <div class="video-grid" style="grid-template-columns: repeat(3, 1fr);">
                <div class="card" style="text-align:center;"><h3>Total User</h3><h2 style="color:var(--primary);"><?= $totalUser ?></h2></div>
                <div class="card" style="text-align:center;"><h3>Total Video</h3><h2 style="color:var(--gold);"><?= $totalVid ?></h2></div>
                <div class="card" style="text-align:center;"><h3>Pending Bayar</h3><h2 style="color:var(--danger);"><?= $pending ?></h2></div>
            </div>
        </div>
    </div>
</body></html>
PHPEOF

cat > "$WEB_ROOT/admin/videos.php" << 'PHPEOF'
<?php require '../config.php'; if(!isAdmin()) exit;
if($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_FILES['video'])) {
    $title = $_POST['title']; $fn = time() . '_' . basename($_FILES['video']['name']);
    if(move_uploaded_file($_FILES['video']['tmp_name'], "../uploads/videos/" . $fn)) {
        $pdo->prepare("INSERT INTO videos (title, filename) VALUES (?,?)")->execute([$title, $fn]);
    }
}
$videos = $pdo->query("SELECT * FROM videos ORDER BY id DESC")->fetchAll();
?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><title>Video Manager</title><link rel="stylesheet" href="../assets/style.css"></head>
<body>
    <button class="mobile-toggle" onclick="document.querySelector('.sidebar').classList.toggle('open')"><i class="fas fa-bars"></i></button>
    <div class="admin-layout">
        <div class="sidebar">
            <h2 style="color:var(--gold); margin-bottom:20px;"><i class="fas fa-shield-alt"></i> Admin VGK</h2>
            <a href="index.php"><i class="fas fa-home"></i> Dashboard</a>
            <a href="videos.php" class="active"><i class="fas fa-video"></i> Video Manager</a>
            <a href="users.php"><i class="fas fa-users"></i> Users</a>
            <a href="finance.php"><i class="fas fa-money-bill-wave"></i> Keuangan</a>
            <a href="console.php"><i class="fas fa-terminal"></i> Console Log</a>
            <a href="settings.php"><i class="fas fa-cog"></i> Settings</a>
        </div>
        <div class="admin-content">
            <h1>Video Manager</h1>
            <div class="card">
                <h3>Upload Video Baru</h3>
                <form method="POST" enctype="multipart/form-data">
                    <div class="form-group"><label>Judul</label><input type="text" name="title" required></div>
                    <div class="form-group"><label>File MP4</label><input type="file" name="video" accept="video/mp4" required></div>
                    <button class="btn btn-primary">Upload</button>
                </form>
            </div>
            <div class="card">
                <table style="width:100%; text-align:left; border-collapse:collapse;">
                    <tr style="border-bottom:1px solid var(--border);"><th>Judul</th><th>Nama File</th><th>Aksi</th></tr>
                    <?php foreach($videos as $v): ?>
                    <tr><td style="padding:10px;"><?= htmlspecialchars($v['title']) ?></td><td><?= $v['filename'] ?></td><td><a href="#" style="color:var(--danger);">Hapus</a></td></tr>
                    <?php endforeach; ?>
                </table>
            </div>
        </div>
    </div>
</body></html>
PHPEOF

cat > "$WEB_ROOT/admin/finance.php" << 'PHPEOF'
<?php require '../config.php'; if(!isAdmin()) exit;
if($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action'])) {
    $tid = (int)$_POST['tid']; $uid = (int)$_POST['uid'];
    if($_POST['action'] == 'approve') {
        $pdo->prepare("UPDATE transactions SET status='success' WHERE id=?")->execute([$tid]);
        $pdo->prepare("UPDATE users SET plan='premium', plan_expires=DATE_ADD(NOW(), INTERVAL 30 DAY) WHERE id=?")->execute([$uid]);
    } elseif($_POST['action'] == 'cancel') {
        $pdo->prepare("UPDATE transactions SET status='failed' WHERE id=?")->execute([$tid]);
    }
    header('Location: finance.php'); exit;
}
$trx = $pdo->query("SELECT t.*, u.username FROM transactions t LEFT JOIN users u ON t.user_id=u.id ORDER BY t.id DESC")->fetchAll();
?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><title>Keuangan</title><link rel="stylesheet" href="../assets/style.css"></head>
<body>
    <button class="mobile-toggle" onclick="document.querySelector('.sidebar').classList.toggle('open')"><i class="fas fa-bars"></i></button>
    <div class="admin-layout">
        <div class="sidebar">
            <h2 style="color:var(--gold); margin-bottom:20px;"><i class="fas fa-shield-alt"></i> Admin VGK</h2>
            <a href="index.php"><i class="fas fa-home"></i> Dashboard</a>
            <a href="videos.php"><i class="fas fa-video"></i> Video Manager</a>
            <a href="users.php"><i class="fas fa-users"></i> Users</a>
            <a href="finance.php" class="active"><i class="fas fa-money-bill-wave"></i> Keuangan</a>
            <a href="console.php"><i class="fas fa-terminal"></i> Console Log</a>
            <a href="settings.php"><i class="fas fa-cog"></i> Settings</a>
        </div>
        <div class="admin-content">
            <h1>Approval Pembayaran</h1>
            <div class="card">
                <table style="width:100%; text-align:left; border-collapse:collapse;">
                    <tr style="border-bottom:1px solid var(--border);"><th>User</th><th>Bukti</th><th>Status</th><th>Aksi</th></tr>
                    <?php foreach($trx as $t): ?>
                    <tr style="border-bottom:1px solid var(--border);">
                        <td style="padding:10px;"><?= $t['username'] ?></td>
                        <td><a href="../uploads/<?= $t['proof_image'] ?>" target="_blank" style="color:var(--primary);">Lihat Bukti</a></td>
                        <td><?= strtoupper($t['status']) ?></td>
                        <td>
                            <?php if($t['status'] == 'pending'): ?>
                            <form method="POST" style="display:inline;"><input type="hidden" name="tid" value="<?= $t['id'] ?>"><input type="hidden" name="uid" value="<?= $t['user_id'] ?>"><button name="action" value="approve" class="btn btn-gold" style="padding:5px;">Approve</button></form>
                            <form method="POST" style="display:inline;"><input type="hidden" name="tid" value="<?= $t['id'] ?>"><button name="action" value="cancel" class="btn btn-danger" style="padding:5px;">Cancel</button></form>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                </table>
            </div>
        </div>
    </div>
</body></html>
PHPEOF

cat > "$WEB_ROOT/admin/settings.php" << 'PHPEOF'
<?php require '../config.php'; if(!isAdmin()) exit;
$set = getSettings($pdo);
if($_SERVER['REQUEST_METHOD'] == 'POST') {
    $qris = $set['qris_manual'];
    if(isset($_FILES['qris_file']) && $_FILES['qris_file']['error'] == 0) {
        $fn = 'qris_' . time() . '_' . $_FILES['qris_file']['name'];
        move_uploaded_file($_FILES['qris_file']['tmp_name'], '../uploads/' . $fn);
        $qris = $fn;
    }
    $pdo->prepare("UPDATE settings SET site_name=?, qris_manual=? WHERE id=1")->execute([$_POST['site_name'], $qris]);
    header('Location: settings.php'); exit;
}
?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><title>Settings</title><link rel="stylesheet" href="../assets/style.css"></head>
<body>
    <button class="mobile-toggle" onclick="document.querySelector('.sidebar').classList.toggle('open')"><i class="fas fa-bars"></i></button>
    <div class="admin-layout">
        <div class="sidebar">
            <h2 style="color:var(--gold); margin-bottom:20px;"><i class="fas fa-shield-alt"></i> Admin VGK</h2>
            <a href="index.php"><i class="fas fa-home"></i> Dashboard</a>
            <a href="videos.php"><i class="fas fa-video"></i> Video Manager</a>
            <a href="users.php"><i class="fas fa-users"></i> Users</a>
            <a href="finance.php"><i class="fas fa-money-bill-wave"></i> Keuangan</a>
            <a href="console.php"><i class="fas fa-terminal"></i> Console Log</a>
            <a href="settings.php" class="active"><i class="fas fa-cog"></i> Settings</a>
        </div>
        <div class="admin-content">
            <h1>Pengaturan Web</h1>
            <div class="card">
                <form method="POST" enctype="multipart/form-data">
                    <div class="form-group"><label>Nama Website</label><input type="text" name="site_name" value="<?= $set['site_name'] ?>" required></div>
                    <div class="form-group"><label>QRIS Manual (Upload)</label><input type="file" name="qris_file"></div>
                    <?php if($set['qris_manual']): ?><img src="../uploads/<?= $set['qris_manual'] ?>" style="width:150px; margin-bottom:20px;"><?php endif; ?>
                    <button class="btn btn-primary">Simpan Perubahan</button>
                </form>
            </div>
        </div>
    </div>
</body></html>
PHPEOF

# ==========================================
# 5. SETUP NGINX & SSL
# ==========================================
echo -e "${CYAN}[4/6] Setup Nginx & SSL...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;
    root $WEB_ROOT;
    index index.php index.html;
    client_max_body_size 3000M;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    location ~ /\.ht { deny all; }
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/var/run/php/php8.3-fpm.sock; fastcgi_read_timeout 300; }
}
NGINXEOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 && systemctl reload nginx
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 777 "$WEB_ROOT/uploads"
systemctl restart php8.3-fpm

SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
DOMAIN_IP=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | head -1)
if [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1; fi
PROTO="https"; [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]] && PROTO="http"

echo -e "${GREEN}[5/6] Selesai!${NC}"
clear
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ INSTALASI ASUPAN VGK v8.0 BERHASIL!    ║${NC}"
echo -e "${GREEN}║  🚀 Manual QRIS • Admin Approval • Paywall ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 Web Utama:${NC} $PROTO://$DOMAIN"
echo -e "${MAGENTA}🔒 Admin Panel:${NC} $PROTO://$DOMAIN/admin/"
echo ""
echo -e "${WHITE}🔑 Login Admin:${NC}"
echo -e "   Username : ${WHITE}admin${NC}"
echo -e "   Password : ${WHITE}Rend11#${NC}"
echo ""
echo -e "${GREEN}🚀 Buka webnya, upload QRIS di menu Settings, dan mulai jualan!${NC}"

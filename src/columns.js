// 表示する SNS の一覧。ここに追加すれば列が増える。
// domains: この列の中で開いてよいドメイン（それ以外のリンクは既定のブラウザで開く）
const COLUMNS = [
  {
    id: 'youtube',
    name: 'YouTube',
    color: '#ff0033',
    home: 'https://www.youtube.com/',
    domains: ['youtube.com', 'youtu.be', 'google.com', 'gstatic.com', 'googleusercontent.com'],
  },
  {
    id: 'x',
    name: 'X',
    color: '#e7e9ea',
    home: 'https://x.com/home',
    domains: ['x.com', 'twitter.com', 'twimg.com'],
  },
  {
    id: 'instagram',
    name: 'Instagram',
    color: '#e1306c',
    home: 'https://www.instagram.com/',
    domains: ['instagram.com', 'cdninstagram.com', 'facebook.com', 'fbcdn.net'],
  },
  {
    id: 'threads',
    name: 'Threads',
    color: '#a0a0ff',
    home: 'https://www.threads.com/',
    domains: ['threads.com', 'threads.net', 'instagram.com', 'facebook.com'],
  },
];

// どの列でも開いてよいログイン用ドメイン（「Google でログイン」など）
const AUTH_DOMAINS = ['accounts.google.com', 'appleid.apple.com', 'facebook.com', 'instagram.com'];

module.exports = { COLUMNS, AUTH_DOMAINS };

module.exports = {
  apps: [{
    name: 'knobler-relay',
    script: './src/index.js',
    cwd: __dirname,
    instances: 1,
    exec_mode: 'fork',
    kill_timeout: 10000,
    max_memory_restart: '200M',
    env: { NODE_ENV: 'production', PORT: 8477 },
  }],
};

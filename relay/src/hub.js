// Hub de conexões vivas: 1 socket por device + heartbeat.
function createHub() {
  const conns = new Map(); // deviceId -> ws

  function add(deviceId, ws) {
    const old = conns.get(deviceId);
    if (old && old !== ws) old.close(1000, 'replaced');
    ws.isAlive = true;
    conns.set(deviceId, ws);
  }

  function remove(deviceId, ws) {
    if (conns.get(deviceId) === ws) conns.delete(deviceId);
  }

  function isOnline(deviceId) {
    const ws = conns.get(deviceId);
    return !!ws && ws.readyState === ws.OPEN;
  }

  function send(deviceId, obj) {
    const ws = conns.get(deviceId);
    if (!ws || ws.readyState !== ws.OPEN) return false;
    ws.send(JSON.stringify(obj));
    return true;
  }

  function markAlive(deviceId) {
    const ws = conns.get(deviceId);
    if (ws) ws.isAlive = true;
  }

  function heartbeat() {
    for (const [deviceId, ws] of conns) {
      if (ws.isAlive === false) { ws.terminate(); conns.delete(deviceId); continue; }
      ws.isAlive = false;
      ws.ping();
    }
  }

  function closeAll(code = 1001) {
    for (const ws of conns.values()) ws.close(code, 'shutdown');
    conns.clear();
  }

  return { add, remove, isOnline, send, markAlive, heartbeat, closeAll, size: () => conns.size };
}

module.exports = { createHub };

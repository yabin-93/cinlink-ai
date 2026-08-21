const [method, parameterMode, parameterValue] = process.argv.slice(2);

if (!method) {
  throw new Error('Usage: node tools/cdp-command.mjs <method> [params-json | --params-base64 base64]');
}

const paramsJson = parameterMode === '--params-base64'
  ? Buffer.from(parameterValue ?? '', 'base64').toString('utf8')
  : (parameterMode ?? '{}');
const params = JSON.parse(paramsJson);

if (method === '--decode-only') {
  process.stdout.write(JSON.stringify(params));
  process.exit(0);
}

const targets = await fetch('http://127.0.0.1:9222/json/list').then((response) => response.json());
const target = targets.find((item) => item.type === 'page');

if (!target) {
  throw new Error('No page target found on port 9222.');
}

const socket = new WebSocket(target.webSocketDebuggerUrl);
const id = 1;

const result = await new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error(`Timed out waiting for ${method}`)), 10000);

  socket.addEventListener('open', () => {
    socket.send(JSON.stringify({ id, method, params }));
  });

  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== id) return;
    clearTimeout(timeout);
    if (message.error) reject(new Error(JSON.stringify(message.error)));
    else resolve(message.result);
    socket.close();
  });

  socket.addEventListener('error', (event) => {
    clearTimeout(timeout);
    reject(event.error ?? new Error('WebSocket error'));
  });
});

process.stdout.write(JSON.stringify(result, null, 2));

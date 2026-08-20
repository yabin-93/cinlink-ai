const [selector, ...files] = process.argv.slice(2);

if (!selector || files.length === 0) {
  throw new Error('Usage: node tools/cdp-upload.mjs <selector> <file> [file...]');
}

const targets = await fetch('http://127.0.0.1:9222/json/list').then((response) => response.json());
const target = targets.find((item) => item.type === 'page');

if (!target) {
  throw new Error('No page target found on port 9222.');
}

const socket = new WebSocket(target.webSocketDebuggerUrl);
let nextId = 1;
const pending = new Map();

function send(method, params = {}) {
  const id = nextId++;
  socket.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
  });
}

const chooser = new Promise((resolve) => {
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.method === 'Page.fileChooserOpened') resolve(message.params);
  });
});

socket.addEventListener('message', (event) => {
  const message = JSON.parse(event.data);
  if (!message.id || !pending.has(message.id)) return;
  const { resolve, reject } = pending.get(message.id);
  pending.delete(message.id);
  if (message.error) reject(new Error(JSON.stringify(message.error)));
  else resolve(message.result);
});

await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, { once: true });
  socket.addEventListener('error', reject, { once: true });
});

await send('Page.enable');
await send('Page.setInterceptFileChooserDialog', { enabled: true });

const click = await send('Runtime.evaluate', {
  expression: `document.querySelector(${JSON.stringify(selector)})?.click()`,
  returnByValue: true,
});

if (click.result?.subtype === 'null') {
  throw new Error(`No element matched selector: ${selector}`);
}

const { backendNodeId } = await Promise.race([
  chooser,
  new Promise((_, reject) => setTimeout(() => reject(new Error('Timed out waiting for file chooser')), 10000)),
]);

await send('DOM.setFileInputFiles', { backendNodeId, files });
await send('Page.setInterceptFileChooserDialog', { enabled: false });
socket.close();

process.stdout.write(JSON.stringify({ selector, files }, null, 2));

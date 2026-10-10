// 上部バーと各列の見出しを描画し、各列の本体の位置をメインプロセスに伝える。
// SNS の画面そのものはメインプロセスが本体の位置に重ねて表示している。

const api = window.crossover;
const columnsEl = document.getElementById('columns');
const togglesEl = document.getElementById('toggles');
const emptyEl = document.getElementById('empty');
const template = document.getElementById('column-template');

let columns = [];
let visible = {};
let maximized = null; // 大きく表示中の列 id
let fullScreen = null; // 動画などを全画面表示中の列 id
const elements = new Map(); // id -> section 要素

function shownIds() {
  const solo = fullScreen ?? maximized;
  return columns.map((c) => c.id).filter((id) => visible[id] && (!solo || id === solo));
}

function render() {
  const shown = new Set(shownIds());
  for (const [id, el] of elements) {
    el.hidden = !shown.has(id);
    el.classList.toggle('is-maximized', id === maximized);
  }
  for (const button of togglesEl.querySelectorAll('button')) {
    button.setAttribute('aria-pressed', String(!!visible[button.dataset.id]));
  }
  document.body.classList.toggle('is-fullscreen', fullScreen !== null);
  emptyEl.hidden = shown.size > 0;
  scheduleLayout();
}

let layoutPending = false;
function scheduleLayout() {
  if (layoutPending) return;
  layoutPending = true;
  requestAnimationFrame(() => {
    layoutPending = false;
    const shown = new Set(shownIds());
    api.setLayout(
      columns.map(({ id }) => {
        if (!shown.has(id)) return { id, bounds: null };
        const r = elements.get(id).querySelector('.column-body').getBoundingClientRect();
        return {
          id,
          bounds: {
            x: Math.round(r.left),
            y: Math.round(r.top),
            width: Math.max(1, Math.round(r.width)),
            height: Math.max(1, Math.round(r.height)),
          },
        };
      }),
    );
  });
}

function buildToggle(column) {
  const button = document.createElement('button');
  button.className = 'toggle';
  button.dataset.id = column.id;
  button.style.setProperty('--accent', column.color);
  button.textContent = column.name;
  button.title = `${column.name} の表示を切り替え`;
  button.addEventListener('click', () => {
    visible[column.id] = !visible[column.id];
    if (maximized === column.id && !visible[column.id]) maximized = null;
    api.setVisible({ [column.id]: visible[column.id] });
    render();
  });
  togglesEl.append(button);
}

function buildColumn(column, zoom) {
  const el = template.content.firstElementChild.cloneNode(true);
  el.dataset.id = column.id;
  el.style.setProperty('--accent', column.color);
  el.querySelector('.name').textContent = column.name;
  el.querySelector('.zoom').textContent = `${Math.round(zoom * 100)}%`;
  el.querySelector('.actions').addEventListener('click', (event) => {
    const button = event.target.closest('button');
    if (!button) return;
    const { action } = button.dataset;
    if (action === 'maximize') {
      maximized = maximized === column.id ? null : column.id;
      render();
    } else {
      api.action(column.id, action);
    }
  });
  // 見出しをダブルクリックでも大きく表示を切り替え
  el.querySelector('.column-header').addEventListener('dblclick', (event) => {
    if (event.target.closest('button')) return;
    maximized = maximized === column.id ? null : column.id;
    render();
  });
  columnsEl.append(el);
  elements.set(column.id, el);
}

function applyState(id, state) {
  const el = elements.get(id);
  if (!el) return;
  if ('loading' in state) el.classList.toggle('is-loading', state.loading);
  if ('title' in state) el.querySelector('.name').title = state.title || '';
  if ('canGoBack' in state) el.querySelector('[data-action="back"]').disabled = !state.canGoBack;
  if ('canGoForward' in state) el.querySelector('[data-action="forward"]').disabled = !state.canGoForward;
  if ('zoom' in state) el.querySelector('.zoom').textContent = `${Math.round(state.zoom * 100)}%`;
}

async function main() {
  const init = await api.init();
  columns = init.columns;
  visible = init.visible;
  for (const column of columns) {
    buildToggle(column);
    buildColumn(column, init.zoom[column.id]);
  }

  document.getElementById('reload-all').addEventListener('click', () => api.action('*', 'reload'));
  api.onState(applyState);
  api.onFullScreen((id) => {
    fullScreen = id;
    render();
  });
  new ResizeObserver(scheduleLayout).observe(columnsEl);
  window.addEventListener('resize', scheduleLayout);

  render();
}

main();

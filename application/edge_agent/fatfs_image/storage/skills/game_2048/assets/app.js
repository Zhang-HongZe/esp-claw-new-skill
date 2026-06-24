const BOARD_SIZE = 4;
const STORAGE_KEY = "esp_claw_game_2048_state";
const BEST_KEY = "esp_claw_game_2048_best";
const WIN_VALUE = 2048;
const SWIPE_THRESHOLD = 24;

const boardEl = document.getElementById("board");
const scoreEl = document.getElementById("score");
const bestEl = document.getElementById("best");
const statusEl = document.getElementById("status");
const restartButton = document.getElementById("restart");
const overlayEl = document.getElementById("overlay");
const overlayTagEl = document.getElementById("overlay-tag");
const overlayTitleEl = document.getElementById("overlay-title");
const overlayTextEl = document.getElementById("overlay-text");
const continueButton = document.getElementById("continue");
const overlayRestartButton = document.getElementById("overlay-restart");

const scoreCards = Array.from(document.querySelectorAll(".score-card"));
const dirButtons = Array.from(document.querySelectorAll(".dir-button"));

const state = {
  board: createEmptyBoard(),
  score: 0,
  best: loadBestScore(),
  gameOver: false,
  won: false,
  keepPlaying: false,
  freshTileId: null,
  lastGain: 0,
};

let touchStart = null;
let touchCurrent = null;
let scoreBumpTimer = null;

function createEmptyBoard() {
  return Array.from({ length: BOARD_SIZE }, () => Array(BOARD_SIZE).fill(0));
}

function loadBestScore() {
  const value = Number(localStorage.getItem(BEST_KEY) || "0");
  return Number.isFinite(value) && value > 0 ? value : 0;
}

function saveBestScore() {
  localStorage.setItem(BEST_KEY, String(state.best));
}

function saveState() {
  const payload = {
    board: state.board,
    score: state.score,
    best: state.best,
    gameOver: state.gameOver,
    won: state.won,
    keepPlaying: state.keepPlaying,
  };
  localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
}

function restoreState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      return false;
    }
    const parsed = JSON.parse(raw);
    if (!isValidBoard(parsed.board)) {
      return false;
    }

    state.board = parsed.board.map((row) => row.slice(0, BOARD_SIZE));
    state.score = Number(parsed.score) || 0;
    state.best = Math.max(loadBestScore(), Number(parsed.best) || 0, state.score);
    state.gameOver = parsed.gameOver === true;
    state.won = parsed.won === true;
    state.keepPlaying = parsed.keepPlaying === true;
    state.freshTileId = null;
    state.lastGain = 0;
    return true;
  } catch (_error) {
    return false;
  }
}

function isValidBoard(board) {
  return (
    Array.isArray(board) &&
    board.length === BOARD_SIZE &&
    board.every(
      (row) =>
        Array.isArray(row) &&
        row.length === BOARD_SIZE &&
        row.every((value) => Number.isInteger(value) && value >= 0),
    )
  );
}

function startNewGame() {
  state.board = createEmptyBoard();
  state.score = 0;
  state.gameOver = false;
  state.won = false;
  state.keepPlaying = false;
  state.lastGain = 0;
  placeRandomTile();
  placeRandomTile();
  hideOverlay();
  setStatus("向任意方向滑动开始。");
  saveState();
  render();
}

function placeRandomTile() {
  const empties = [];
  for (let row = 0; row < BOARD_SIZE; row += 1) {
    for (let col = 0; col < BOARD_SIZE; col += 1) {
      if (state.board[row][col] === 0) {
        empties.push({ row, col });
      }
    }
  }
  if (!empties.length) {
    state.freshTileId = null;
    return;
  }

  const spot = empties[Math.floor(Math.random() * empties.length)];
  const value = Math.random() < 0.9 ? 2 : 4;
  state.board[spot.row][spot.col] = value;
  state.freshTileId = `${spot.row}-${spot.col}`;
}

function render() {
  bestEl.textContent = String(state.best);
  scoreEl.textContent = String(state.score);
  let hasBump = false;
  scoreCards.forEach((card, index) => {
    const shouldBump =
      (index === 0 && state.lastGain > 0) ||
      (index === 1 && state.best === state.score && state.score > 0 && state.lastGain > 0);
    card.classList.toggle("bump", shouldBump);
    hasBump = hasBump || shouldBump;
  });

  boardEl.innerHTML = "";
  for (let i = 0; i < BOARD_SIZE * BOARD_SIZE; i += 1) {
    const cell = document.createElement("div");
    cell.className = "cell";
    boardEl.appendChild(cell);
  }

  for (let row = 0; row < BOARD_SIZE; row += 1) {
    for (let col = 0; col < BOARD_SIZE; col += 1) {
      const value = state.board[row][col];
      const tile = document.createElement("div");
      tile.className = "tile";
      tile.classList.add(value === 0 ? "value-0" : value > WIN_VALUE ? "value-super" : `value-${value}`);
      if (`${row}-${col}` === state.freshTileId && value !== 0) {
        tile.classList.add("fresh");
      }
      tile.style.gridRow = String(row + 1);
      tile.style.gridColumn = String(col + 1);
      tile.textContent = value === 0 ? "" : String(value);
      tile.style.fontSize = fontSizeForValue(value);
      boardEl.appendChild(tile);
    }
  }

  if (scoreBumpTimer) {
    window.clearTimeout(scoreBumpTimer);
    scoreBumpTimer = null;
  }
  if (hasBump) {
    scoreBumpTimer = window.setTimeout(() => {
      scoreCards.forEach((card) => card.classList.remove("bump"));
      scoreBumpTimer = null;
    }, 240);
  }
}

function fontSizeForValue(value) {
  if (value >= 1024) {
    return "clamp(1.5rem, 4vw, 2.35rem)";
  }
  if (value >= 128) {
    return "clamp(1.8rem, 4.8vw, 2.7rem)";
  }
  return "clamp(2rem, 6vw, 3rem)";
}

function largestTile(board) {
  return Math.max(...board.flat());
}

function cloneBoard(board) {
  return board.map((row) => row.slice());
}

function boardsEqual(a, b) {
  for (let row = 0; row < BOARD_SIZE; row += 1) {
    for (let col = 0; col < BOARD_SIZE; col += 1) {
      if (a[row][col] !== b[row][col]) {
        return false;
      }
    }
  }
  return true;
}

function reverseRows(board) {
  return board.map((row) => row.slice().reverse());
}

function transpose(board) {
  const next = createEmptyBoard();
  for (let row = 0; row < BOARD_SIZE; row += 1) {
    for (let col = 0; col < BOARD_SIZE; col += 1) {
      next[col][row] = board[row][col];
    }
  }
  return next;
}

function collapseLine(line) {
  const values = line.filter((value) => value !== 0);
  const merged = [];
  let scoreGain = 0;

  for (let i = 0; i < values.length; i += 1) {
    if (values[i] !== 0 && values[i] === values[i + 1]) {
      const value = values[i] * 2;
      merged.push(value);
      scoreGain += value;
      i += 1;
    } else {
      merged.push(values[i]);
    }
  }

  while (merged.length < BOARD_SIZE) {
    merged.push(0);
  }

  return { line: merged, scoreGain };
}

function move(direction) {
  if (state.gameOver) {
    setStatus("本局已经结束，重新开始再冲一次。");
    return;
  }
  if (state.won && !state.keepPlaying) {
    showWinOverlay();
    return;
  }

  const original = cloneBoard(state.board);
  let working = cloneBoard(state.board);

  if (direction === "up" || direction === "down") {
    working = transpose(working);
  }
  if (direction === "right" || direction === "down") {
    working = reverseRows(working);
  }

  let totalGain = 0;
  working = working.map((row) => {
    const result = collapseLine(row);
    totalGain += result.scoreGain;
    return result.line;
  });

  if (direction === "right" || direction === "down") {
    working = reverseRows(working);
  }
  if (direction === "up" || direction === "down") {
    working = transpose(working);
  }

  if (boardsEqual(original, working)) {
    setStatus("这一步没有变化，换个方向试试。");
    state.lastGain = 0;
    render();
    return;
  }

  state.board = working;
  state.score += totalGain;
  state.lastGain = totalGain;
  state.best = Math.max(state.best, state.score);
  saveBestScore();
  placeRandomTile();

  const canContinue = hasMoves(state.board);
  if (!state.won && largestTile(state.board) >= WIN_VALUE) {
    state.won = true;
    state.gameOver = !canContinue;
    showWinOverlay(canContinue);
    setStatus(
      canContinue
        ? "你已经拼出 2048 了，还可以继续冲更高分。"
        : "你拼出了 2048，并且这一局已经没有后续可走的位置。",
    );
  } else if (!canContinue) {
    state.gameOver = true;
    showGameOverOverlay();
    setStatus("没有可移动的位置了。");
  } else if (totalGain > 0) {
    setStatus(`漂亮，这一步拿到 ${totalGain} 分。`);
    hideOverlay();
  } else {
    setStatus("继续合并，把大数挤到角落里。");
    hideOverlay();
  }

  saveState();
  render();
}

function hasMoves(board) {
  for (let row = 0; row < BOARD_SIZE; row += 1) {
    for (let col = 0; col < BOARD_SIZE; col += 1) {
      const value = board[row][col];
      if (value === 0) {
        return true;
      }
      if (row + 1 < BOARD_SIZE && board[row + 1][col] === value) {
        return true;
      }
      if (col + 1 < BOARD_SIZE && board[row][col + 1] === value) {
        return true;
      }
    }
  }
  return false;
}

function setStatus(text) {
  statusEl.textContent = text;
}

function showWinOverlay(canContinue = true) {
  overlayTagEl.textContent = canContinue ? "New Peak" : "Perfect Finish";
  overlayTitleEl.textContent = "2048!";
  overlayTextEl.textContent = canContinue
    ? "你已经达成目标，可以继续挑战更高分，或者直接开新局。"
    : "这一局已经圆满收官。想继续玩的话，直接再开一局。";
  continueButton.classList.toggle("hidden", !canContinue);
  overlayEl.classList.remove("hidden");
}

function showGameOverOverlay() {
  overlayTagEl.textContent = "Round Over";
  overlayTitleEl.textContent = "没有空位了";
  overlayTextEl.textContent = "下一局试试把最大数字稳稳放在一个角落里。";
  continueButton.classList.add("hidden");
  overlayEl.classList.remove("hidden");
}

function hideOverlay() {
  overlayEl.classList.add("hidden");
}

function handleKey(event) {
  const keyMap = {
    ArrowUp: "up",
    ArrowDown: "down",
    ArrowLeft: "left",
    ArrowRight: "right",
    w: "up",
    W: "up",
    a: "left",
    A: "left",
    s: "down",
    S: "down",
    d: "right",
    D: "right",
  };

  const direction = keyMap[event.key];
  if (!direction) {
    return;
  }

  event.preventDefault();
  move(direction);
}

function handlePointerStart(event) {
  const point = getPoint(event);
  touchStart = point;
  touchCurrent = point;
}

function handlePointerMove(event) {
  if (!touchStart) {
    return;
  }
  touchCurrent = getPoint(event);
}

function handlePointerEnd(event) {
  if (!touchStart) {
    return;
  }

  const endPoint = getPoint(event) || touchCurrent || touchStart;
  const dx = endPoint.x - touchStart.x;
  const dy = endPoint.y - touchStart.y;

  touchStart = null;
  touchCurrent = null;

  if (Math.abs(dx) < SWIPE_THRESHOLD && Math.abs(dy) < SWIPE_THRESHOLD) {
    return;
  }

  if (Math.abs(dx) > Math.abs(dy)) {
    move(dx > 0 ? "right" : "left");
  } else {
    move(dy > 0 ? "down" : "up");
  }
}

function getPoint(event) {
  if (!event) {
    return null;
  }
  if (event.changedTouches && event.changedTouches[0]) {
    return { x: event.changedTouches[0].clientX, y: event.changedTouches[0].clientY };
  }
  if (event.touches && event.touches[0]) {
    return { x: event.touches[0].clientX, y: event.touches[0].clientY };
  }
  if (typeof event.clientX === "number" && typeof event.clientY === "number") {
    return { x: event.clientX, y: event.clientY };
  }
  return null;
}

function continuePlay() {
  state.keepPlaying = true;
  hideOverlay();
  setStatus("继续吧，看看你能把数字推到多高。");
  saveState();
}

function initBoardSurface() {
  boardEl.addEventListener("touchstart", handlePointerStart, { passive: true });
  boardEl.addEventListener("touchmove", handlePointerMove, { passive: true });
  boardEl.addEventListener("touchend", handlePointerEnd, { passive: true });
  boardEl.addEventListener("touchcancel", handlePointerEnd, { passive: true });

  boardEl.addEventListener("pointerdown", handlePointerStart);
  boardEl.addEventListener("pointermove", handlePointerMove);
  boardEl.addEventListener("pointerup", handlePointerEnd);
  boardEl.addEventListener("pointercancel", handlePointerEnd);
}

function initControls() {
  restartButton.addEventListener("click", startNewGame);
  overlayRestartButton.addEventListener("click", startNewGame);
  continueButton.addEventListener("click", continuePlay);
  dirButtons.forEach((button) => {
    button.addEventListener("click", () => {
      move(button.dataset.dir);
    });
  });
  window.addEventListener("keydown", handleKey, { passive: false });
}

function init() {
  const restored = restoreState();
  if (!restored) {
    startNewGame();
    return;
  }

  if (state.best < state.score) {
    state.best = state.score;
  }
  saveBestScore();
  if (!hasMoves(state.board)) {
    state.gameOver = true;
  }

  if (state.won && !state.keepPlaying) {
    showWinOverlay(!state.gameOver);
    setStatus(
      state.gameOver
        ? "上次已经拼到 2048，并且棋盘也走到了终局。"
        : "上次已经拼到 2048 了，继续冲或者直接重开。",
    );
  } else if (state.gameOver) {
    showGameOverOverlay();
    setStatus(state.won ? "上次你已经拼到 2048，并最终停在了残局。" : "上次停在了残局，来一局新的吧。");
  } else {
    hideOverlay();
    setStatus("已恢复上次进度，继续滑动。");
  }

  render();
}

initBoardSurface();
initControls();
init();

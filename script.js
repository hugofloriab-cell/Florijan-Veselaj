const STORAGE_KEY = "tasks";

const taskForm = document.getElementById("task-form");
const taskInput = document.getElementById("task-input");
const categorySelect = document.getElementById("category-select");
const categoryFilter = document.getElementById("category-filter");
const taskList = document.getElementById("task-list");
const emptyState = document.getElementById("empty-state");
const progressFill = document.getElementById("progress-fill");
const progressLabel = document.getElementById("progress-label");
const progressPercent = document.getElementById("progress-percent");
const filterButtons = document.querySelectorAll(".filter-btn");

let tasks = loadTasks();
let statusFilter = "all";
let categoryFilterValue = "all";

function loadTasks() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function saveTasks() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks));
}

function addTask(text, category) {
  tasks.push({
    id: crypto.randomUUID(),
    text,
    category,
    completed: false,
  });
  saveTasks();
  render();
}

function toggleTask(id) {
  const task = tasks.find((t) => t.id === id);
  if (task) task.completed = !task.completed;
  saveTasks();
  render();
}

function deleteTask(id) {
  tasks = tasks.filter((t) => t.id !== id);
  saveTasks();
  render();
}

function getFilteredTasks() {
  return tasks.filter((t) => {
    const statusOk =
      statusFilter === "all" ||
      (statusFilter === "active" && !t.completed) ||
      (statusFilter === "completed" && t.completed);
    const categoryOk =
      categoryFilterValue === "all" || t.category === categoryFilterValue;
    return statusOk && categoryOk;
  });
}

function render() {
  const filtered = getFilteredTasks();

  taskList.innerHTML = "";
  filtered.forEach((task) => {
    const li = document.createElement("li");
    li.className = "task-item" + (task.completed ? " completed" : "");

    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.className = "task-checkbox";
    checkbox.checked = task.completed;
    checkbox.addEventListener("change", () => toggleTask(task.id));

    const text = document.createElement("span");
    text.className = "task-text";
    text.textContent = task.text;

    const category = document.createElement("span");
    category.className = "task-category";
    category.textContent = task.category;

    const deleteBtn = document.createElement("button");
    deleteBtn.className = "delete-btn";
    deleteBtn.textContent = "✕";
    deleteBtn.setAttribute("aria-label", "Supprimer la tâche");
    deleteBtn.addEventListener("click", () => deleteTask(task.id));

    li.append(checkbox, text, category, deleteBtn);
    taskList.appendChild(li);
  });

  emptyState.classList.toggle("visible", filtered.length === 0);

  updateProgress();
}

function updateProgress() {
  const total = tasks.length;
  const done = tasks.filter((t) => t.completed).length;
  const percent = total === 0 ? 0 : Math.round((done / total) * 100);

  progressFill.style.width = percent + "%";
  progressPercent.textContent = percent + "%";
  progressLabel.textContent = `${done} / ${total} tâches terminées`;
}

taskForm.addEventListener("submit", (e) => {
  e.preventDefault();
  const text = taskInput.value.trim();
  if (!text) return;
  addTask(text, categorySelect.value);
  taskInput.value = "";
  taskInput.focus();
});

filterButtons.forEach((btn) => {
  btn.addEventListener("click", () => {
    filterButtons.forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    statusFilter = btn.dataset.filter;
    render();
  });
});

categoryFilter.addEventListener("change", () => {
  categoryFilterValue = categoryFilter.value;
  render();
});

render();

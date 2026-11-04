"use strict";

const $ = (id) => document.getElementById(id);
const money = (value) => new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 2 }).format(Number(value));
const number = (value) => new Intl.NumberFormat("vi-VN").format(value);
const state = { page: 1, pageSize: 12, total: 0, query: "", status: "all", items: [], editing: null, deleting: null, removeImage: false, busy: false, preview: null, load: null };
let toastTimer;

function message(text) {
  $("toast").textContent = text;
  $("toast").hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { $("toast").hidden = true; }, 4000);
}

async function api(path, options = {}) {
  let response;
  try { response = await fetch(path, { ...options, headers: { ...(options.body && !(options.body instanceof FormData) ? { "Content-Type": "application/json" } : {}), ...options.headers } }); }
  catch (error) {
    if (error.name === "AbortError") throw error;
    throw new Error("Không kết nối được API. Kiểm tra backend rồi thử lại.");
  }
  if (!response.ok) {
    let detail;
    try { detail = (await response.json()).detail; } catch { /* Proxy can return HTML. */ }
    if (Array.isArray(detail)) detail = detail.map((issue) => `${issue.loc.at(-1)}: ${issue.msg}`).join("; ");
    throw new Error(detail || (response.status === 413 ? "File quá lớn. Hãy chọn ảnh dưới 5 MB." : `Yêu cầu thất bại (HTTP ${response.status}). Vui lòng thử lại.`));
  }
  return response.status === 204 ? null : response.json();
}

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function action(label, symbol, fn, className = "") {
  const button = element("button", `icon-button ${className}`, symbol);
  button.type = "button";
  button.setAttribute("aria-label", label);
  button.title = label;
  button.addEventListener("click", fn);
  return button;
}

function renderProducts() {
  $("products").replaceChildren();
  for (const product of state.items) {
    const row = document.createElement("tr");
    const nameCell = document.createElement("td");
    const cell = element("div", "product-cell");
    const thumbnail = element("div", "product-thumb", "◇");
    if (product.image_url) {
      const img = document.createElement("img");
      img.src = product.image_url; img.alt = product.name; img.loading = "lazy";
      img.addEventListener("error", () => { thumbnail.textContent = "◇"; });
      thumbnail.replaceChildren(img);
    }
    const text = element("div", "product-text");
    text.append(element("strong", "", product.name), element("small", "", product.description || `ID: ${product.id.slice(0, 8).toUpperCase()}`));
    cell.append(thumbnail, text); nameCell.append(cell);
    const quantity = element("td", "stock", number(product.stock)); quantity.append(element("small", "", "đơn vị"));
    const availability = product.stock === 0 ? ["empty-stock", "Hết hàng"] : product.stock <= 5 ? ["low", "Sắp hết"] : ["available", "Còn hàng"];
    const status = document.createElement("td"); status.append(element("span", `badge ${availability[0]}`, availability[1]));
    const actions = element("div", "row-actions");
    if (product.image_url) {
      const link = element("a", "icon-button", "↓");
      link.href = `/api/products/${product.id}/image?download=true`;
      link.setAttribute("aria-label", `Tải ảnh ${product.name}`); link.title = "Tải ảnh";
      actions.append(link);
    }
    actions.append(action(`Sửa ${product.name}`, "✎", () => openEditor(product)), action(`Xóa ${product.name}`, "×", () => openDelete(product), "delete"));
    const actionsCell = document.createElement("td"); actionsCell.append(actions);
    row.append(nameCell, element("td", "", product.category), element("td", "price", money(product.price)), quantity, status, actionsCell);
    $("products").append(row);
  }
  $("table-wrap").hidden = state.items.length === 0;
  $("empty").hidden = state.items.length !== 0;
  const filtered = Boolean(state.query || state.status !== "all");
  $("empty-title").textContent = filtered ? "Không tìm thấy sản phẩm phù hợp" : "Danh mục đang chờ sản phẩm đầu tiên";
  $("empty-description").textContent = filtered ? "Thử một từ khóa khác hoặc thay đổi bộ lọc tồn kho." : "Thêm tên, giá và một bức ảnh. Bắt đầu từ những điều đơn giản.";
  $("empty-add").hidden = filtered;
  $("result-count").textContent = number(state.total);
  const start = (state.page - 1) * state.pageSize + 1;
  $("page-label").textContent = state.total ? `Hiển thị ${start}–${Math.min(start + state.items.length - 1, state.total)} trong ${number(state.total)} sản phẩm` : "Chưa có sản phẩm phù hợp";
  $("page-number").textContent = String(state.page).padStart(2, "0");
  $("previous").disabled = state.page <= 1;
  $("next").disabled = state.page * state.pageSize >= state.total;
}

async function loadProducts() {
  state.load?.abort();
  const controller = new AbortController(); state.load = controller;
  $("loading").hidden = false; $("load-error").hidden = true;
  $("table-wrap").hidden = true; $("empty").hidden = true;
  $("previous").disabled = true; $("next").disabled = true;
  const params = new URLSearchParams({ q: state.query, status: state.status, page: state.page, page_size: state.pageSize });
  try {
    const [data, summary] = await Promise.all([api(`/api/products?${params}`, { signal: controller.signal }), api("/api/summary", { signal: controller.signal })]);
    if (state.load !== controller) return;
    if (state.page > 1 && !data.items.length) { state.page = Math.max(1, Math.ceil(data.total / state.pageSize)); return loadProducts(); }
    state.items = data.items; state.total = data.total;
    $("stat-products").textContent = number(summary.products);
    $("nav-count").textContent = number(summary.products);
    $("stat-units").textContent = number(summary.units);
    $("stat-value").textContent = money(summary.inventory_value);
    $("stat-low").textContent = number(summary.low_stock);
    $("connection").className = "connection online";
    $("connection").querySelector("span").textContent = "API đang hoạt động";
    renderProducts();
  } catch (error) {
    if (error.name === "AbortError" || state.load !== controller) return;
    $("load-error").hidden = false; $("load-error-text").textContent = error.message;
    $("connection").className = "connection offline";
    $("connection").querySelector("span").textContent = "Chưa kết nối API";
    for (const id of ["stat-products", "stat-units", "stat-value", "stat-low", "nav-count", "result-count"]) $(id).textContent = "—";
    $("page-label").textContent = "Không tải được dữ liệu";
  } finally { if (state.load === controller) $("loading").hidden = true; }
}

function showImage(url) {
  $("image-preview").replaceChildren();
  if (url) { const img = document.createElement("img"); img.src = url; img.alt = "Xem trước ảnh sản phẩm"; $("image-preview").append(img); }
  else $("image-preview").append(element("span", "", "▧"));
}

async function openEditor(product = null) {
  if (state.busy) return;
  if (product) {
    try { product = await api(`/api/products/${product.id}`); }
    catch (error) { message(error.message); return; }
  }
  state.editing = product; state.removeImage = false;
  $("product-form").reset(); $("form-error").hidden = true;
  $("dialog-title").textContent = product ? "Chỉnh sửa sản phẩm" : "Thêm sản phẩm";
  $("product-name").value = product?.name || "";
  $("product-category").value = product?.category || "";
  $("product-description").value = product?.description || "";
  $("product-price").value = product?.price ?? "";
  $("product-stock").value = product?.stock ?? "";
  $("file-name").textContent = "";
  $("remove-image").hidden = !product?.image_url;
  showImage(product?.image_url);
  $("product-dialog").showModal();
  $("product-name").focus();
}

function closeEditor() {
  if (state.busy) return;
  $("product-dialog").close();
}
$("product-dialog").addEventListener("close", () => {
  if (state.preview) URL.revokeObjectURL(state.preview);
  state.preview = null;
});
$("product-dialog").addEventListener("cancel", (event) => { if (state.busy) event.preventDefault(); });
document.querySelectorAll(".close-dialog").forEach((button) => button.addEventListener("click", closeEditor));

$("product-image").addEventListener("change", () => {
  const file = $("product-image").files[0];
  if (state.preview) URL.revokeObjectURL(state.preview);
  state.preview = null;
  if (!file) { showImage(state.removeImage ? null : state.editing?.image_url); return; }
  if (file.size > 5 * 1024 * 1024 || !["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
    $("product-image").value = ""; $("file-name").textContent = "";
    $("form-error").textContent = "Hãy chọn ảnh JPG, PNG hoặc WebP có dung lượng tối đa 5 MB.";
    $("form-error").hidden = false;
    showImage(state.removeImage ? null : state.editing?.image_url); return;
  }
  $("form-error").hidden = true; state.removeImage = false;
  state.preview = URL.createObjectURL(file); showImage(state.preview);
  $("file-name").textContent = file.name;
});
$("remove-image").addEventListener("click", () => {
  state.removeImage = true; $("product-image").value = ""; $("file-name").textContent = "Ảnh sẽ được xóa khi lưu.";
  showImage(null); $("remove-image").hidden = true;
});

$("product-form").addEventListener("submit", async (event) => {
  event.preventDefault(); if (state.busy) return;
  const body = { name: $("product-name").value.trim(), category: $("product-category").value.trim(),
    price: $("product-price").value, stock: Number($("product-stock").value), description: $("product-description").value.trim() };
  if (!body.name || !body.category) { $("form-error").textContent = "Tên và danh mục không được để trống."; $("form-error").hidden = false; return; }
  const file = $("product-image").files[0];
  state.busy = true; $("form-error").hidden = true;
  $("product-form").querySelectorAll("button,input,textarea").forEach((node) => { node.disabled = true; });
  $("save-product").textContent = "Đang lưu…";
  let saved = false;
  try {
    const edited = Boolean(state.editing);
    if (edited) body.version = state.editing.version;
    const product = await api(edited ? `/api/products/${state.editing.id}` : "/api/products", { method: edited ? "PUT" : "POST", body: JSON.stringify(body) });
    // Keep the new id/version if image upload fails; retry must not duplicate a product.
    state.editing = product; saved = true;
    $("dialog-title").textContent = "Chỉnh sửa sản phẩm";
    if (file) {
      const form = new FormData(); form.append("file", file);
      state.editing = await api(`/api/products/${product.id}/image?version=${product.version}`, { method: "POST", body: form });
    } else if (state.removeImage && product.image_url) {
      await api(`/api/products/${product.id}/image?version=${product.version}`, { method: "DELETE" });
    }
    state.busy = false; closeEditor(); state.page = 1;
    message(edited ? "Đã cập nhật sản phẩm." : "Đã thêm sản phẩm mới.");
    await loadProducts();
  } catch (error) {
    $("form-error").textContent = (saved ? "Thông tin đã lưu nhưng xử lý ảnh chưa thành công. " : "") + error.message;
    $("form-error").hidden = false;
    if (saved) await loadProducts();
  } finally {
    state.busy = false;
    $("product-form").querySelectorAll("button,input,textarea").forEach((node) => { node.disabled = false; });
    $("save-product").textContent = "Lưu sản phẩm";
  }
});

function openDelete(product) {
  state.deleting = product;
  $("delete-message").textContent = `Bạn muốn xóa “${product.name}” khỏi danh mục?`;
  $("delete-error").hidden = true; $("delete-dialog").showModal(); $("delete-cancel").focus();
}
for (const id of ["delete-cancel", "delete-close"]) $(id).addEventListener("click", () => { if (!state.busy) $("delete-dialog").close(); });
$("delete-dialog").addEventListener("cancel", (event) => { if (state.busy) event.preventDefault(); });
$("delete-confirm").addEventListener("click", async () => {
  if (state.busy) return;
  state.busy = true; $("delete-confirm").disabled = true; $("delete-confirm").textContent = "Đang xóa…";
  try {
    await api(`/api/products/${state.deleting.id}?version=${state.deleting.version}`, { method: "DELETE" });
    $("delete-dialog").close(); message("Đã xóa sản phẩm."); await loadProducts();
  } catch (error) { $("delete-error").textContent = error.message; $("delete-error").hidden = false; }
  finally { state.busy = false; $("delete-confirm").disabled = false; $("delete-confirm").textContent = "Xóa sản phẩm"; }
});

for (const id of ["add-product", "empty-add"]) $(id).addEventListener("click", () => openEditor());
for (const id of ["refresh", "retry"]) $(id).addEventListener("click", loadProducts);
let searchTimer;
$("search").addEventListener("input", () => { clearTimeout(searchTimer); searchTimer = setTimeout(() => { state.query = $("search").value; state.page = 1; loadProducts(); }, 300); });
$("stock-filter").addEventListener("change", () => { state.status = $("stock-filter").value; state.page = 1; loadProducts(); });
$("previous").addEventListener("click", () => { if (state.page > 1) { state.page--; loadProducts(); } });
$("next").addEventListener("click", () => { if (state.page * state.pageSize < state.total) { state.page++; loadProducts(); } });
loadProducts();

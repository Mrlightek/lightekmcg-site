export function element(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) {
    if (name.startsWith("on")) node.addEventListener(name.slice(2), value);
    else if (value !== undefined && value !== false) node.setAttribute(name, value === true ? "" : value);
  }
  node.append(...children.filter(child => child != null));
  return node;
}

export const button = (label, click, attrs = {}) => element("button", { type: "button", onclick: click, ...attrs }, label);
export const label = (name, field) => element("label", {}, name, field);

export function select(options, selected, change) {
  const field = element("select", { onchange: e => change(e.target.value) },
    ...options.map(([value, name]) => element("option", { value }, name)));
  field.value = String(selected ?? "");
  return field;
}

export function number(value, change, { min, max, step = "any", name } = {}) {
  return element("input", {
    type: "number", value, min, max, step, "aria-label": name,
    onchange: e => {
      const field = e.target;
      if (!field.value.length || !field.checkValidity()) {
        field.reportValidity();
        field.value = value ?? "";
        if (value == null && !field.value.length && !field.validity.badInput) change(undefined);
        return;
      }
      change(field.valueAsNumber);
    }
  });
}

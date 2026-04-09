// Minimal Mustache-style template compiler replacing hogan.js.
// Supports: {{var}}, {{{var}}}, {{#section}}...{{/section}}, {{^section}}...{{/section}}

function escapeHtml(s) {
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function render(template, context) {
  // Inverted sections: {{^key}}...{{/key}}
  let result = template.replaceAll(
    /\{\{\^(\w+)\}\}([\s\S]*?)\{\{\/\1\}\}/g,
    (_, key, inner) => (!context[key] ? render(inner, context) : "")
  );

  // Sections: {{#key}}...{{/key}}
  result = result.replaceAll(
    /\{\{#(\w+)\}\}([\s\S]*?)\{\{\/\1\}\}/g,
    (_, key, inner) => (context[key] ? render(inner, context) : "")
  );

  // Unescaped interpolation: {{{key}}}
  result = result.replaceAll(
    /\{\{\{(\w+)\}\}\}/g,
    (_, key) => (context[key] != null ? String(context[key]) : "")
  );

  // Escaped interpolation: {{key}}
  result = result.replaceAll(
    /\{\{(\w+)\}\}/g,
    (_, key) => (context[key] != null ? escapeHtml(context[key]) : "")
  );

  return result;
}

export default {
  compile(template) {
    return { render: (context) => render(template, context) };
  },
};

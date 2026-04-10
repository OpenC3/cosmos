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

const INVERTED_SECTION_RE = /\{\{\^(\w+)\}\}([\s\S]*?)\{\{\/\1\}\}/g;
const SECTION_RE = /\{\{#(\w+)\}\}([\s\S]*?)\{\{\/\1\}\}/g;
const UNESCAPED_RE = /\{\{\{(\w+)\}\}\}/g;
const ESCAPED_RE = /\{\{(\w+)\}\}/g;

function render(template, context) {
  // Inverted sections: {{^key}}...{{/key}}
  let result = template.replaceAll(
    INVERTED_SECTION_RE,
    (_, key, inner) => (context[key] ? "" : render(inner, context))
  );

  // Sections: {{#key}}...{{/key}}
  result = result.replaceAll(
    SECTION_RE,
    (_, key, inner) => (context[key] ? render(inner, context) : "")
  );

  // Unescaped interpolation: {{{key}}}
  result = result.replaceAll(
    UNESCAPED_RE,
    (_, key) => (context[key] == null ? "" : String(context[key]))
  );

  // Escaped interpolation: {{key}}
  result = result.replaceAll(
    ESCAPED_RE,
    (_, key) => (context[key] == null ? "" : escapeHtml(context[key]))
  );

  return result;
}

export default {
  compile(template) {
    return { render: (context) => render(template, context) };
  },
};

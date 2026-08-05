// Empty stand-in for monaco's css / html / json / typescript language service
// registrations. See the monacoLanguageServiceStub plugin in vite.config.js
// for why they get dropped. Monaco's index.js re-exports each of these as a
// namespace (monaco.css, monaco.html, ...) so an empty module is enough - the
// namespaces just come out empty and nothing in COSMOS reads them.
export {}

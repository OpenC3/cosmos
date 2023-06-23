import singleSpaSvelte from "single-spa-svelte";
import App from "./App.svelte";
import "../build/smui.css";

const svelteLifecycles = singleSpaSvelte({
  component: App,
  domElementGetter: function () {
    let elem = document.getElementById("openc3-tool");
    if (elem) {
      return elem;
    } else {
      return new HTMLElement();
    }
  },
});

export const { bootstrap, mount, unmount } = svelteLifecycles;

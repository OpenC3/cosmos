// Taken from https://docusaurus.io/docs/markdown-features/react#mdx-component-scope
// Import the original mapper
import MDXComponents from "@theme-original/MDXComponents";
import Tabs from "@theme/Tabs";
import TabItem from "@theme/TabItem";

export default {
  // Reuse the default mapping
  ...MDXComponents,
  Tabs,
  TabItem,
};

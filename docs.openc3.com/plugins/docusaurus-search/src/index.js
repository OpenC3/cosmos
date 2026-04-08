const fs = require("fs");
const os = require("os");
const path = require("path");
const MiniSearch = require("minisearch");
const { Worker } = require("worker_threads");

// local imports
const utils = require("./utils");

module.exports = function (context, options) {
  options = options || {};
  let clientGenerated = false;

  const guid = String(Date.now());
  const fileNames = {
    searchDoc: `search-doc-${guid}.json`,
    lunrIndex: `lunr-index-${guid}.json`,
  };

  return {
    name: "docusaurus-search",
    getThemePath() {
      return path.resolve(__dirname, "./theme");
    },
    configureWebpack(config) {
      if (!clientGenerated) {
        const generatedFilesDir = config.resolve.alias["@generated"];
        utils.generateMiniSearchClientJS(generatedFilesDir);
        clientGenerated = true;
      }
      return {};
    },
    async contentLoaded({ actions }) {
      actions.setGlobalData({ fileNames: fileNames });
    },
    async postBuild({ routesPaths = [], outDir, baseUrl, plugins }) {
      console.log(
        "docusaurus-search:: Building search docs and lunr index file",
      );
      console.time("docusaurus-search:: Indexing time");

      const docsPlugin = plugins.find(
        (plugin) => plugin.name == "docusaurus-plugin-content-docs",
      );

      const [files, meta] = utils.getFilePaths(
        routesPaths,
        outDir,
        baseUrl,
        options,
      );
      if (meta.excludedCount) {
        console.log(
          `docusaurus-search:: ${meta.excludedCount} documents were excluded from the search by excludeRoutes config`,
        );
      }

      const fields = {
        title: { boost: 200, ...options.fields?.title },
        content: { boost: 2, ...options.fields?.content },
        keywords: { boost: 100, ...options.fields?.keywords },
      };

      const searchDocuments = [];
      const miniSearch = new MiniSearch({
        idField: "id",
        fields: ["title", "content", "keywords"],
        storeFields: ["title", "content", "keywords"],
        searchOptions: {
          boost: Object.fromEntries(
            Object.entries(fields).map(([k, v]) => [k, v.boost || 1]),
          ),
          prefix: true,
        },
        processTerm: (term) => {
          if (options.stopWords && options.stopWords.includes(term)) {
            return null;
          }
          return term.toLowerCase();
        },
      });

      const loadedVersions =
        docsPlugin &&
        !docsPlugin.options.disableVersioning &&
        !(options.disableVersioning ?? false)
          ? docsPlugin.content.loadedVersions.reduce(function (
              accum,
              currentVal,
            ) {
              accum[currentVal.versionName] = currentVal.label;
              return accum;
            }, {})
          : null;

      const addToSearchData = (d) => {
        if (options.excludeTags && options.excludeTags.includes(d.tagName)) {
          return;
        }
        const doc = {
          id: searchDocuments.length,
          title: d.title,
          content: d.content,
          keywords: d.keywords,
        };
        miniSearch.add(doc);
        searchDocuments.push(d);
      };

      const indexedDocuments = await buildSearchData(
        files,
        addToSearchData,
        loadedVersions,
      );
      console.timeEnd("docusaurus-search:: Indexing time");
      console.log(
        `docusaurus-search:: indexed ${indexedDocuments} documents out of ${files.length}`,
      );

      const searchDocFileContents = JSON.stringify({
        searchDocs: searchDocuments,
        options,
      });
      console.log("docusaurus-search:: writing search-doc.json");
      fs.writeFileSync(
        path.join(outDir, "search-doc.json"),
        searchDocFileContents,
      );
      console.log(`docusaurus-search:: writing ${fileNames.searchDoc}`);
      fs.writeFileSync(
        path.join(outDir, fileNames.searchDoc),
        searchDocFileContents,
      );

      const indexFileContents = JSON.stringify(miniSearch);
      console.log("docusaurus-search:: writing lunr-index.json");
      fs.writeFileSync(path.join(outDir, "lunr-index.json"), indexFileContents);
      console.log(`docusaurus-search:: writing ${fileNames.lunrIndex}`);
      fs.writeFileSync(
        path.join(outDir, fileNames.lunrIndex),
        indexFileContents,
      );
      console.log("docusaurus-search:: End of process");
    },
  };
};

function buildSearchData(files, addToSearchData, loadedVersions) {
  if (!files.length) {
    return Promise.resolve();
  }
  let activeWorkersCount = 0;
  const workerCount = Math.max(2, os.cpus().length);

  console.log(
    `docusaurus-search:: Start scanning documents in ${Math.min(workerCount, files.length)} threads`,
  );
  let indexedDocuments = 0;

  return new Promise((resolve, reject) => {
    let nextIndex = 0;

    const handleMessage = ([isDoc, payload], worker) => {
      if (isDoc) {
        addToSearchData(payload);
      } else {
        indexedDocuments += payload;

        if (nextIndex < files.length) {
          worker.postMessage(files[nextIndex++]);
        } else {
          worker.postMessage(null);
        }
      }
    };

    for (let i = 0; i < workerCount; i++) {
      if (nextIndex >= files.length) {
        break;
      }
      const worker = new Worker(path.join(__dirname, "html-to-doc.mjs"), {
        workerData: {
          loadedVersions: loadedVersions,
        },
      });
      worker.on("error", reject);
      worker.on("message", (message) => {
        handleMessage(message, worker);
      });
      worker.on("exit", (code) => {
        if (code !== 0) {
          reject(new Error(`Scanner stopped with exit code ${code}`));
        } else {
          activeWorkersCount--;
          if (activeWorkersCount <= 0) {
            resolve(indexedDocuments);
          }
        }
      });

      activeWorkersCount++;
      worker.postMessage(files[nextIndex++]);
    }
  });
}

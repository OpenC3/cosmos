module.exports = {
  testEnvironment: "jsdom",
  transform: {
    "^.+\\.svelte$": "svelte-jester",
    "^.+\\.js$": "babel-jest",
  },
  moduleFileExtensions: ["js", "svelte"],
  setupFilesAfterEnv: ["@testing-library/jest-dom"],
};

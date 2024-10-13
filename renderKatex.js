// Script for rendering math offline using KaTeX.
// Call with `node renderKatex.js <postDir> [--watch]`.
// Reads the file <postDir>/source.md, replaces math with rendered HTML,
// and writes it to <postDir>/index.md.

const katex = require("katex");
const fs = require("fs");
const path = require("path");

// input path given as an argument
// for easy use with `entr`
const inputPath = process.argv[2];
const dir = path.dirname(inputPath);
const outputPath = `${dir}/index.md`;
if (inputPath == outputPath) {
  throw new Error("Input file must not be called index.md");
}

const render = () => {
  let content = fs.readFileSync(inputPath).toString();

  for (const { re, displayMode } of [
    { re: /\$\$(.+?)\$\$/ms, displayMode: true },
    { re: /\$(.+?)\$/ms, displayMode: false },
  ]) {
    let match;
    while ((match = content.match(re))) {
      // console.log(match[1]);
      const rendered = katex
        .renderToString(match[1], {
          throwOnError: false,
          displayMode,
        })
        // replace underscores so they come out of the markdown renderer correctly
        .replace("_", "\\_");
      content =
        content.substring(0, match.index) +
        rendered +
        content.substring(match.index + match[0].length);
    }
  }

  fs.writeFileSync(outputPath, content);

  console.log(`wrote ${outputPath}`);
};

render();

if (process.argv[3] === "--watch") {
  fs.watchFile(inputPath, render);
}

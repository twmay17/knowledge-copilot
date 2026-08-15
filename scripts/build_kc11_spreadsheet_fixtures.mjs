import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const require = createRequire(import.meta.url);
const { SpreadsheetFile, Workbook } = require("@oai/artifact-tool");
const execFileAsync = promisify(execFile);

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, "..");
const fixtureDirectory = path.join(repositoryRoot, "fixtures", "spreadsheet-ingestion");
const previewDirectory = path.join(repositoryRoot, "outputs", "kc11-spreadsheet-fixtures");

await fs.mkdir(fixtureDirectory, { recursive: true });
await fs.mkdir(previewDirectory, { recursive: true });

const workbook = Workbook.create();
const operatingStatement = workbook.worksheets.add("Operating Statement");
const assumptions = workbook.worksheets.add("Assumptions");

operatingStatement.showGridLines = false;
operatingStatement.freezePanes.freezeRows(1);
operatingStatement.getRange("A1:F4").values = [
  ["Metric", "Period", "Actual", "Budget", "Variance", "Unit"],
  ["Room Revenue", 2020, 3285000, 3400000, null, "USD"],
  ["Available Room Nights", 2020, 36500, 36600, null, "room_nights"],
  ["RevPAR", 2020, null, null, null, "USD_per_available_room"],
];
operatingStatement.getRange("E2").formulas = [["=C2-D2"]];
operatingStatement.getRange("E2:E3").fillDown();
operatingStatement.getRange("C4:E4").formulas = [["=C2/C3", "=D2/D3", "=C4-D4"]];
operatingStatement.getRange("A1:F1").format = {
  fill: "#17365D",
  font: { bold: true, color: "#FFFFFF" },
};
operatingStatement.getRange("A2:B4").format.font = { color: "#000000" };
operatingStatement.getRange("C2:D3").format.font = { color: "#0000FF" };
operatingStatement.getRange("C4:E4").format.font = { color: "#000000" };
operatingStatement.getRange("E2:E3").format.font = { color: "#000000" };
operatingStatement.getRange("C2:E3").format.numberFormat = "$#,##0.00";
operatingStatement.getRange("C4:E4").format.numberFormat = "$0.00";
operatingStatement.getRange("A1:F4").format.borders = {
  preset: "all",
  style: "thin",
  color: "#D9E2F3",
};
operatingStatement.getRange("A1:F4").format.wrapText = true;
operatingStatement.getRange("A1:F4").format.autofitColumns();
operatingStatement.getRange("A1:F4").format.autofitRows();
operatingStatement.getRange("A1").format.columnWidth = 26;
operatingStatement.getRange("F1").format.columnWidth = 24;

assumptions.showGridLines = false;
assumptions.freezePanes.freezeRows(1);
assumptions.getRange("A1:D5").values = [
  ["Variable", "Period", "Value", "Unit"],
  ["Occupancy", 2020, 0.725, "ratio"],
  ["ADR", 2020, 123.45, "USD"],
  ["Implied RevPAR", 2020, null, "USD_per_available_room"],
  ["Reported RevPAR", 2020, null, "USD_per_available_room"],
];
assumptions.getRange("C4").formulas = [["=C2*C3"]];
assumptions.getRange("C5").formulas = [["='Operating Statement'!C4"]];
assumptions.getRange("A1:D1").format = {
  fill: "#17365D",
  font: { bold: true, color: "#FFFFFF" },
};
assumptions.getRange("C2:C3").format.font = { color: "#0000FF" };
assumptions.getRange("C4").format.font = { color: "#000000" };
assumptions.getRange("C5").format.font = { color: "#008000" };
assumptions.getRange("C2").format.numberFormat = "0.0%";
assumptions.getRange("C3:C5").format.numberFormat = "$0.00";
assumptions.getRange("A1:D5").format.borders = {
  preset: "all",
  style: "thin",
  color: "#D9E2F3",
};
assumptions.getRange("A1:D5").format.wrapText = true;
assumptions.getRange("A1:D5").format.autofitColumns();
assumptions.getRange("A1:D5").format.autofitRows();
assumptions.getRange("A1").format.columnWidth = 22;
assumptions.getRange("D1").format.columnWidth = 24;

const formulaInspection = await workbook.inspect({
  kind: "formula",
  sheetId: "Operating Statement",
  range: "A1:F4",
  maxChars: 4000,
  options: { maxResults: 20 },
});
const valueInspection = await workbook.inspect({
  kind: "table",
  sheetId: "Assumptions",
  range: "A1:D5",
  include: "values,formulas",
  maxChars: 4000,
});
console.log(JSON.stringify({ formulaInspection, valueInspection }, null, 2));

for (const sheetName of ["Operating Statement", "Assumptions"]) {
  const preview = await workbook.render({
    sheetName,
    autoCrop: "all",
    scale: 1.5,
    format: "png",
  });
  const filename = sheetName.toLowerCase().replaceAll(" ", "-") + ".png";
  await fs.writeFile(
    path.join(previewDirectory, filename),
    new Uint8Array(await preview.arrayBuffer()),
  );
}

const xlsx = await SpreadsheetFile.exportXlsx(workbook);
const rawWorkbookPath = path.join(previewDirectory, "sample-evidence.raw.xlsx");
const workbookPath = path.join(fixtureDirectory, "sample-evidence.xlsx");
await xlsx.save(rawWorkbookPath);
await normalizeXlsx(rawWorkbookPath, workbookPath);
await fs.rm(rawWorkbookPath, { force: true });
await fs.rm(`${workbookPath}.inspect.ndjson`, { force: true });

const csv = [
  "Metric,Period,Actual,Unit,Note",
  'Occupancy,2020,0.725,ratio,"Synthetic, quoted note"',
  'ADR,2020,123.45,USD,"Escaped ""reviewed"" value"',
  'RevPAR,2020,89.50,USD_per_available_room,"Contains a',
  'multiline note"',
].join("\r\n");
await Workbook.fromCSV(csv, { sheetName: "CSV Evidence" });
await fs.writeFile(path.join(fixtureDirectory, "sample-evidence.csv"), csv, "utf8");

console.log(`Wrote fixtures to ${fixtureDirectory}`);
console.log(`Wrote previews to ${previewDirectory}`);

async function normalizeXlsx(inputPath, outputPath) {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), "kc11-xlsx-"));
  try {
    await execFileAsync("/usr/bin/unzip", ["-qq", inputPath, "-d", temporaryDirectory]);
    await normalizeRelationshipIdentifiers(temporaryDirectory);
    const files = await listFiles(temporaryDirectory);
    const fixedTimestamp = new Date("2000-01-01T00:00:00Z");
    for (const file of files) {
      await fs.utimes(path.join(temporaryDirectory, file), fixedTimestamp, fixedTimestamp);
    }
    await fs.rm(outputPath, { force: true });
    await execFileAsync("/usr/bin/zip", ["-X", "-q", outputPath, ...files], {
      cwd: temporaryDirectory,
    });
  } finally {
    await fs.rm(temporaryDirectory, { recursive: true, force: true });
  }
}

async function normalizeRelationshipIdentifiers(directory) {
  await replaceIdentifiers(
    path.join(directory, "_rels", ".rels"),
    /Id="[^"]+"/g,
    ["Id=\"rId1\""],
  );
  await replaceIdentifiers(
    path.join(directory, "xl", "_rels", "workbook.xml.rels"),
    /Id="[^"]+"/g,
    [
      "Id=\"rId1\"",
      "Id=\"rId2\"",
      "Id=\"rId3\"",
      "Id=\"rId4\"",
      "Id=\"rId5\"",
    ],
  );
  await replaceIdentifiers(
    path.join(directory, "xl", "workbook.xml"),
    /r:id="[^"]+"/g,
    ["r:id=\"rId4\"", "r:id=\"rId5\""],
  );
}

async function replaceIdentifiers(file, expression, replacements) {
  const source = await fs.readFile(file, "utf8");
  let index = 0;
  const normalized = source.replace(expression, () => {
    if (index >= replacements.length) {
      throw new Error(`Unexpected relationship identifier count in ${file}`);
    }
    return replacements[index++];
  });
  if (index !== replacements.length) {
    throw new Error(`Expected ${replacements.length} relationship identifiers in ${file}`);
  }
  await fs.writeFile(file, normalized, "utf8");
}

async function listFiles(directory, relativeDirectory = "") {
  const entries = await fs.readdir(path.join(directory, relativeDirectory), {
    withFileTypes: true,
  });
  const files = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const relativePath = path.join(relativeDirectory, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await listFiles(directory, relativePath)));
    } else if (entry.isFile()) {
      files.push(relativePath);
    }
  }
  return files;
}

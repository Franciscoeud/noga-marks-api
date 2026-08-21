import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourcePath = path.join(
  root,
  "planner-frontend/src/components/storefront/storefront-navigation.json",
);
const targetPath = path.join(
  root,
  "wordpress/wp-content/themes/aurenzi-twentytwentyfive/inc/storefront-navigation.php",
);

const phpEscape = (value) =>
  `'${String(value).replaceAll("\\", "\\\\").replaceAll("'", "\\'")}'`;

const renderLink = (link, indent) =>
  `${indent}array( 'label' => ${phpEscape(link.label)}, 'path' => ${phpEscape(link.path)} ),`;

const renderGroup = (group) => {
  const lines = [
    "            array(",
    `                'title' => ${phpEscape(group.title)},`,
  ];
  if (group.path) lines.push(`                'path'  => ${phpEscape(group.path)},`);
  lines.push("                'links' => array(");
  lines.push(...group.links.map((link) => renderLink(link, "                    ")));
  lines.push("                ),", "            ),");
  return lines.join("\n");
};

const renderMenu = (menu) => [
  `        ${phpEscape(menu.id)} => array(`,
  `            'label'  => ${phpEscape(menu.label)},`,
  `            'path'   => ${phpEscape(menu.rootPath)},`,
  "            'groups' => array(",
  menu.groups.map(renderGroup).join("\n"),
  "            ),",
  "        ),",
].join("\n");

const source = JSON.parse(await readFile(sourcePath, "utf8"));
const output = [
  "<?php",
  "/**",
  " * Generated from planner-frontend storefront-navigation.json.",
  " * Run: npm run wordpress:navigation:sync",
  " */",
  "",
  "if ( ! defined( 'ABSPATH' ) ) {",
  "    exit;",
  "}",
  "",
  "function aurenzi_storefront_navigation() {",
  "    return array(",
  source.map(renderMenu).join("\n"),
  "    );",
  "}",
  "",
].join("\n");

if (process.argv.includes("--check")) {
  let current = "";
  try {
    current = await readFile(targetPath, "utf8");
  } catch {
    // A missing generated file is reported as out of date below.
  }
  if (current !== output) {
    process.stderr.write("WordPress navigation is out of date. Run npm run wordpress:navigation:sync.\n");
    process.exitCode = 1;
  }
} else {
  await mkdir(path.dirname(targetPath), { recursive: true });
  await writeFile(targetPath, output, "utf8");
  process.stdout.write(`Updated ${path.relative(root, targetPath)}\n`);
}

const DAVAO_MOUNTAIN_NAMES = [
  "Mt. Apo",
  "Mount Dinor",
  "Mount Loay",
  "Viper's Peak",
  "Mount Megatong",
  "Mt. Hamiguitan",
  "Mt. Kampalili",
  "Mt. Talomo",
];

function normalizeMountainName(value) {
  return value
    .normalize("NFKD")
    .toLocaleLowerCase("en-US")
    .replace(/\bmt\.?/g, "mount")
    .replace(/[^a-z0-9]/g, "");
}

function canonicalizeDavaoMountainName(value) {
  if (typeof value !== "string") return null;
  const normalized = normalizeMountainName(value.trim());
  return DAVAO_MOUNTAIN_NAMES.find(
    (name) => normalizeMountainName(name) === normalized,
  ) || null;
}

module.exports = {
  canonicalizeDavaoMountainName,
  normalizeMountainName,
};

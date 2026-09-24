const DECIMAL_MONEY = /^(-?)(\d+)(?:\.(\d+))?$/;

export function moneyToMinorUnits(value: string | number): bigint {
  const normalized = String(value).trim();
  const match = DECIMAL_MONEY.exec(normalized);
  if (!match) throw new Error(`Invalid monetary value: ${normalized}`);

  const [, sign, whole = "0", fraction = ""] = match;
  const roundedFraction = (fraction + "000").slice(0, 3);
  let minorUnits = BigInt(whole) * 100n + BigInt(roundedFraction.slice(0, 2));
  if (Number(roundedFraction[2]) >= 5) minorUnits += 1n;
  return sign === "-" ? -minorUnits : minorUnits;
}

export function sumMoney(values: ReadonlyArray<string | number>): string {
  const minorUnits = values.reduce((total, value) => total + moneyToMinorUnits(value), 0n);
  const sign = minorUnits < 0n ? "-" : "";
  const absolute = minorUnits < 0n ? -minorUnits : minorUnits;
  return `${sign}${absolute / 100n}.${String(absolute % 100n).padStart(2, "0")}`;
}

export function formatMad(value: string | number): string {
  const minorUnits = moneyToMinorUnits(value);
  const sign = minorUnits < 0n ? "-" : "";
  const absolute = minorUnits < 0n ? -minorUnits : minorUnits;
  const whole = (absolute / 100n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return `${sign}${whole},${String(absolute % 100n).padStart(2, "0")} MAD`;
}

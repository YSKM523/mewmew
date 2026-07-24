interface DateTimeParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

const LOCAL_ISO_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/;

function parseLocalIso(value: string): DateTimeParts {
  const match = LOCAL_ISO_PATTERN.exec(value);
  if (match === null) {
    throw new Error("due_at must be a local ISO8601 date and time");
  }

  const parts: DateTimeParts = {
    year: Number(match[1]),
    month: Number(match[2]),
    day: Number(match[3]),
    hour: Number(match[4]),
    minute: Number(match[5]),
    second: match[6] === undefined ? 0 : Number(match[6]),
  };
  const roundTrip = new Date(
    Date.UTC(
      parts.year,
      parts.month - 1,
      parts.day,
      parts.hour,
      parts.minute,
      parts.second,
    ),
  );
  if (
    roundTrip.getUTCFullYear() !== parts.year ||
    roundTrip.getUTCMonth() + 1 !== parts.month ||
    roundTrip.getUTCDate() !== parts.day ||
    roundTrip.getUTCHours() !== parts.hour ||
    roundTrip.getUTCMinutes() !== parts.minute ||
    roundTrip.getUTCSeconds() !== parts.second
  ) {
    throw new Error("due_at contains an invalid date or time");
  }
  return parts;
}

function partsAt(
  formatter: Intl.DateTimeFormat,
  epochMilliseconds: number,
): DateTimeParts {
  const values: Partial<DateTimeParts> = {};
  for (const part of formatter.formatToParts(epochMilliseconds)) {
    if (
      part.type === "year" ||
      part.type === "month" ||
      part.type === "day" ||
      part.type === "hour" ||
      part.type === "minute" ||
      part.type === "second"
    ) {
      values[part.type] = Number(part.value);
    }
  }

  if (
    values.year === undefined ||
    values.month === undefined ||
    values.day === undefined ||
    values.hour === undefined ||
    values.minute === undefined ||
    values.second === undefined
  ) {
    throw new Error("Intl.DateTimeFormat omitted a required date part");
  }
  return values as DateTimeParts;
}

function asUtcMilliseconds(parts: DateTimeParts): number {
  return Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second,
  );
}

function sameDateTime(left: DateTimeParts, right: DateTimeParts): boolean {
  return (
    left.year === right.year &&
    left.month === right.month &&
    left.day === right.day &&
    left.hour === right.hour &&
    left.minute === right.minute &&
    left.second === right.second
  );
}

export function zonedLocalIsoToUnixSeconds(
  localIso: string,
  timeZone: string,
): number {
  const desired = parseLocalIso(localIso);
  const formatter = new Intl.DateTimeFormat(
    "en-US-u-ca-iso8601-nu-latn",
    {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    },
  );

  const desiredAsUtc = asUtcMilliseconds(desired);
  let candidate = desiredAsUtc;
  for (let iteration = 0; iteration < 6; iteration += 1) {
    const rendered = partsAt(formatter, candidate);
    const correction = desiredAsUtc - asUtcMilliseconds(rendered);
    if (correction === 0) {
      return Math.floor(candidate / 1_000);
    }
    candidate += correction;
  }

  if (!sameDateTime(partsAt(formatter, candidate), desired)) {
    throw new Error("local date and time does not exist in the requested timezone");
  }
  return Math.floor(candidate / 1_000);
}

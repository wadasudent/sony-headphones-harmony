// Discovery is a name-based hint, not manufacturer authentication. Renamed devices
// can also be retained by the address saved after a successful protocol handshake.
export function isSonyHeadphoneName(name: string): boolean {
  const normalized: string = name.trim().toUpperCase().replace(/[\s_\-‐‑–—]/g, '').replace(/^SONY/, '');
  return /^(?:WH|WF|WI|MDR)[A-Z0-9]*\d[A-Z0-9]*$/.test(normalized) ||
    /^(?:LINKBUDS(?:S|OPEN|FIT)?|ULTWEAR)$/.test(normalized) ||
    /^SONY[\s_\-]*(?:HEADPHONES|HEADSET|耳机)$/i.test(name.trim());
}

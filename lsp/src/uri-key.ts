/**
 * Return the stable key used for URI-indexed workspace state.
 *
 * Windows file systems are normally case-insensitive, while URI producers may
 * preserve drive and directory casing differently. Keep the original URI on
 * entries for LSP responses, but fold case for internal identity.
 */
export function workspaceUriKey(uri: string): string {
  let value = uri.trim().replace(/\\/g, "/");
  while (value.endsWith("/")) value = value.slice(0, -1);
  return process.platform === "win32" ? value.toLowerCase() : value;
}

import { ConvexError, v } from "convex/values";
import { mutation, query } from "./_generated/server";

// Bump when the consent text in the app changes; older consents must re-agree before uploading.
export const CONSENT_VERSION = 1;
const MAX_BYTES = 20 * 1024 * 1024; // one dictation zip; a 2 min clip with audio is ~4 MB
const MAX_SESSIONS_PER_DAY = 500;

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function checkInstallId(installId: string) {
  if (!uuid.test(installId)) throw new ConvexError("bad installId");
}

async function activeInstall(ctx: any, installId: string) {
  checkInstallId(installId);
  const install = await ctx.db.query("installs").withIndex("by_install", (q: any) => q.eq("installId", installId)).unique();
  if (!install || install.deletedAt) throw new ConvexError("no consent on file");
  if (install.consentVersion < CONSENT_VERSION) throw new ConvexError("consent out of date");
  return install;
}

/** The user agreed (or changed the audio choice). Idempotent. */
export const consent = mutation({
  args: { installId: v.string(), consentVersion: v.number(), shareAudio: v.boolean(), appVersion: v.string() },
  handler: async (ctx, a) => {
    checkInstallId(a.installId);
    if (a.consentVersion !== CONSENT_VERSION) throw new ConvexError("unknown consent version");
    const existing = await ctx.db.query("installs").withIndex("by_install", (q) => q.eq("installId", a.installId)).unique();
    const fields = { consentVersion: a.consentVersion, shareAudio: a.shareAudio, appVersion: a.appVersion, deletedAt: undefined };
    if (existing) await ctx.db.patch(existing._id, fields);
    else await ctx.db.insert("installs", { installId: a.installId, createdAt: Date.now(), ...fields });
  },
});

/** Step 1 of an upload: a one-time URL the app POSTs the zip to. */
export const uploadUrl = mutation({
  args: { installId: v.string() },
  handler: async (ctx, { installId }) => {
    await activeInstall(ctx, installId);
    const since = Date.now() - 24 * 3600 * 1000;
    const today = await ctx.db.query("sessions").withIndex("by_install", (q) => q.eq("installId", installId))
      .filter((q) => q.gt(q.field("uploadedAt"), since)).take(MAX_SESSIONS_PER_DAY + 1);
    if (today.length > MAX_SESSIONS_PER_DAY) throw new ConvexError("daily upload limit reached");
    return await ctx.storage.generateUploadUrl();
  },
});

/** Step 2: record what was uploaded. Rejects oversize or audio the user didn't agree to share. */
export const finishUpload = mutation({
  args: {
    installId: v.string(), sessionName: v.string(), storageId: v.id("_storage"),
    durationSeconds: v.number(), motionSamples: v.number(), words: v.number(), hasAudio: v.boolean(),
  },
  handler: async (ctx, a) => {
    const install = await activeInstall(ctx, a.installId);
    const meta = await ctx.db.system.get(a.storageId);
    const reject = async (why: string) => { await ctx.storage.delete(a.storageId); throw new ConvexError(why); };
    if (!meta) throw new ConvexError("upload not found");
    if (meta.size > MAX_BYTES) return await reject("too large");
    if (a.hasAudio && !install.shareAudio) return await reject("audio not consented");
    if (!/^[\w-]{1,80}$/.test(a.sessionName)) return await reject("bad sessionName");
    const dup = await ctx.db.query("sessions")
      .withIndex("by_install_session", (q) => q.eq("installId", a.installId).eq("sessionName", a.sessionName)).unique();
    if (dup) { await ctx.storage.delete(a.storageId); return { duplicate: true }; }
    await ctx.db.insert("sessions", {
      installId: a.installId, sessionName: a.sessionName, storageId: a.storageId, bytes: meta.size,
      durationSeconds: a.durationSeconds, motionSamples: a.motionSamples, words: a.words, hasAudio: a.hasAudio,
      uploadedAt: Date.now(),
    });
    return { duplicate: false };
  },
});

/** "Delete my data": removes every uploaded file and session row for this install, and withdraws consent. */
export const deleteMyData = mutation({
  args: { installId: v.string() },
  handler: async (ctx, { installId }) => {
    checkInstallId(installId);
    // ponytail: one mutation handles up to ~4000 sessions (Convex write limits); paginate if anyone exceeds that.
    const rows = await ctx.db.query("sessions").withIndex("by_install", (q) => q.eq("installId", installId)).collect();
    for (const r of rows) { await ctx.storage.delete(r.storageId); await ctx.db.delete(r._id); }
    const install = await ctx.db.query("installs").withIndex("by_install", (q) => q.eq("installId", installId)).unique();
    if (install) await ctx.db.patch(install._id, { deletedAt: Date.now() });
    return { deletedSessions: rows.length };
  },
});

/** What the app shows in Settings: how much this install has contributed. */
export const myStats = query({
  args: { installId: v.string() },
  handler: async (ctx, { installId }) => {
    checkInstallId(installId);
    const rows = await ctx.db.query("sessions").withIndex("by_install", (q) => q.eq("installId", installId)).collect();
    return { sessions: rows.length, words: rows.reduce((s, r) => s + r.words, 0),
             minutes: rows.reduce((s, r) => s + r.durationSeconds, 0) / 60 };
  },
});

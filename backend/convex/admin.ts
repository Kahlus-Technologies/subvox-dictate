import { v } from "convex/values";
import { internalQuery } from "./_generated/server";

/** For us, not the app (internal: callable from the dashboard or `npx convex run`). Download URLs for an install. */
export const sessionFiles = internalQuery({
  args: { installId: v.string() },
  handler: async (ctx, { installId }) => {
    const rows = await ctx.db.query("sessions").withIndex("by_install", (q) => q.eq("installId", installId)).collect();
    return Promise.all(rows.map(async (r) => ({ session: r.sessionName, hasAudio: r.hasAudio, url: await ctx.storage.getUrl(r.storageId) })));
  },
});

import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";
import { internalMutation } from "./_generated/server";

/** Files uploaded but never registered with finishUpload (app quit mid-upload) are deleted after a day. */
export const sweepOrphans = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = Date.now() - 24 * 3600 * 1000;
    const files = await ctx.db.system.query("_storage").filter((q) => q.lt(q.field("_creationTime"), cutoff)).take(500);
    let removed = 0;
    for (const f of files) {
      const used = await ctx.db.query("sessions").withIndex("by_storage", (q) => q.eq("storageId", f._id)).first();
      if (!used) { await ctx.storage.delete(f._id); removed++; }
    }
    return { removed };
  },
});

const crons = cronJobs();
crons.daily("sweep orphan uploads", { hourUTC: 9, minuteUTC: 0 }, internal.crons.sweepOrphans);
export default crons;

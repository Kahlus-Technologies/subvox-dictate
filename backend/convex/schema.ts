import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

// No accounts. An install is a random UUID the app generates once, sent with every request.
export default defineSchema({
  installs: defineTable({
    installId: v.string(),
    consentVersion: v.number(), // which consent text they agreed to
    shareAudio: v.boolean(), // false = motion + timings only, audio.wav is never uploaded
    appVersion: v.string(),
    createdAt: v.number(),
    deletedAt: v.optional(v.number()),
  }).index("by_install", ["installId"]),

  sessions: defineTable({
    installId: v.string(),
    sessionName: v.string(), // e.g. 2026-11-11T184947-348-dictation, unique per install
    storageId: v.id("_storage"), // zip of motion.csv, words.json, meta.json (+ audio.wav if shared)
    bytes: v.number(),
    durationSeconds: v.number(),
    motionSamples: v.number(),
    words: v.number(),
    hasAudio: v.boolean(),
    uploadedAt: v.number(),
  })
    .index("by_install", ["installId"])
    .index("by_install_session", ["installId", "sessionName"])
    .index("by_storage", ["storageId"]),
});

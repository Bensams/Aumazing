// delete-account — permanently deletes the calling user's account and data.
//
// Called by the app (authenticated; JWT verified by the platform) after the
// parent confirms deletion twice in Settings. Removes the user's child
// profiles and their gameplay/assessment rows, then deletes the auth user
// itself. Tables with ON DELETE CASCADE foreign keys to auth.users
// (entitlements, payment_records, research_consents, admin_users) are
// cleaned up automatically by the final admin delete.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  // Resolve the calling user from their JWT (RLS-scoped client).
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (userError || !user) {
    return json({ error: "not authenticated" }, 401);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Never let an admin account delete itself through the app flow.
  const { data: adminRow } = await admin
    .from("admin_users")
    .select("user_id")
    .eq("user_id", user.id)
    .maybeSingle();
  if (adminRow) {
    return json({ error: "admin accounts cannot be deleted from the app" }, 403);
  }

  // Collect this parent's children, then remove child-keyed rows that have
  // no cascading FK back to auth.users.
  const { data: children, error: childrenError } = await admin
    .from("children")
    .select("id")
    .eq("parent_user_id", user.id);
  if (childrenError) {
    console.error("children lookup failed:", childrenError);
    return json({ error: "could not delete account data" }, 500);
  }

  const childIds = (children ?? []).map((c: { id: string }) => c.id);
  if (childIds.length > 0) {
    for (const table of [
      "assessment_results",
      "game_sessions",
      "module_recommendations",
    ]) {
      const { error } = await admin.from(table).delete().in("child_id", childIds);
      if (error) {
        // Log but continue — a missing optional table must not strand the
        // deletion halfway.
        console.error(`${table} cleanup failed:`, error);
      }
    }
    const { error: childDeleteError } = await admin
      .from("children")
      .delete()
      .in("id", childIds);
    if (childDeleteError) {
      console.error("children delete failed:", childDeleteError);
      return json({ error: "could not delete account data" }, 500);
    }
  }

  // Finally delete the auth user; FK cascades clean up the rest.
  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error("auth user delete failed:", deleteError);
    return json({ error: "could not delete account" }, 500);
  }

  return json({ deleted: true });
});

export async function onRequestDelete(context) {
  const { sessionId } = context.params;
  const db = context.env.DB;

  try {
    await db.prepare('DELETE FROM pong_sessions WHERE session_id = ?').bind(sessionId).run();
    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

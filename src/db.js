export function getToday() {
  return new Date().toISOString().split('T')[0];
}

export function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  });
}

export function errorResponse(message, status = 400) {
  return jsonResponse({ error: message }, status);
}

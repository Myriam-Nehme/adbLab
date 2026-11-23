const API = process.env.API_URL || 'http://localhost:5080';
const REQUESTS = Number(process.env.REQUESTS || 10);

async function login(email, password) {
  const response = await fetch(`${API}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password })
  });
  if (!response.ok) throw new Error(`Login failed for ${email}: HTTP ${response.status}`);
  return response.headers.getSetCookie().map((c) => c.split(';')[0]).join('; ');
}

const users = [
  { email: 'demo@tickethub.com', cookie: await login('demo@tickethub.com', 'Demo123!') },
  { email: 'demo2@tickethub.com', cookie: await login('demo2@tickethub.com', 'Demo123!') }
];

const events = await (await fetch(`${API}/api/events`)).json();
const event = events.find((e) => e.seatsLeft > 0);
const seats = await (await fetch(`${API}/api/events/${event.eventId}/seats`)).json();
const seat = seats.find((s) => !s.isTaken);
console.log(`Event #${event.eventId} "${event.title}", seat Row ${seat.row} Seat ${seat.number} (id ${seat.seatId})`);
console.log(`Sending ${REQUESTS} booking requests at the same time...\n`);

const results = await Promise.all(
  Array.from({ length: REQUESTS }, async (_, i) => {
    const user = users[i % users.length];
    const response = await fetch(`${API}/api/bookings`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Cookie: user.cookie },
      body: JSON.stringify({ eventId: event.eventId, seatIds: [seat.seatId] })
    });
    const body = await response.json().catch(() => ({}));
    return { request: i + 1, user: user.email, status: response.status, answer: body.bookingId ? `booking #${body.bookingId}` : body.error };
  })
);

console.table(results);
const created = results.filter((r) => r.status === 201).length;
const conflicts = results.filter((r) => r.status === 409).length;
console.log(`\n201 Created: ${created}   409 Conflict: ${conflicts}   other: ${REQUESTS - created - conflicts}`);
console.log(created === 1 ? 'PASS: the seat was sold exactly once.' : 'CHECK: expected exactly one success.');

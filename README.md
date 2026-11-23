# TicketHub: event ticket booking

GIN401 lab project. A small events company sells seats for concerts and shows.
Customers browse events, pick seats on a seat map and book them; staff create
events and follow sales. The key promise of the system: **a seat is never sold twice**,
even when two people click "Book" at the same moment.

```
 React (web/)  ──HTTP/JSON──►  C# ASP.NET Core Web API (api/)  ──ADO.NET──►  SQL Server (database/)
 seat map, bookings,           hosted on IIS, calls stored                   tables, procedures,
 staff reports                 procedures with parameters                    trigger, indexes
```

## How the project meets the requirements

| Requirement | Where |
|---|---|
| **Design**: keys, constraints, table > 100,000 rows | `database/01_schema.sql`: PK/FK/CHECK/UNIQUE everywhere. `dbo.Ticket` has ~290,000 rows (`02_seed_data.sql`) and is read by every key query |
| **Logic in the database** | `03_logic.sql`: 13 stored procedures, 2 functions (`fn_SeatsLeft` scalar, `fn_EventSales` inline TVF), trigger `trg_Booking_Audit` |
| **Transactions**: TRY…CATCH, two users | `app.usp_BookSeats`, `app.usp_CancelBooking`. Same seat: filtered unique index `UX_Ticket_Event_Seat_Active`. Same customer: `UPDLOCK, HOLDLOCK` on the customer row. Proof: `06_tests.sql`, `07_concurrency_demo.sql`, `scripts/race-test.mjs` |
| **Performance**: plans on the large table | `05_performance.sql`: before/after plans and logical reads for the 3 key queries |
| **Application**: ADO.NET, parameters | `api/`: every call is a stored procedure with typed `SqlParameter`s; the seat list is a table-valued parameter |
| **Security**: least privilege, no password in code | `04_security.sql`: login `TicketHubApp` can only `EXECUTE` schema `app`; direct table access is denied. Connection string in user-secrets / environment variable. Customer passwords stored as salted SHA-256 hashes; user id comes from a signed HttpOnly cookie |

## Business rules

1. A seat can be sold only once per event (cancelled seats can be sold again).
2. No booking for a past or a cancelled event.
3. At most 6 seats per customer per event.
4. The price depends on the seat category (Standard / VIP) and is fixed at booking time.
5. Cancellation is allowed up to 24 hours before the event.
6. Every booking and cancellation is written to an audit table (trigger).
7. Only staff can create events and see sales reports.

## Requirements to run it

- SQL Server 2017 or later (Express or Developer edition is fine) + SSMS
- **SQL Server authentication enabled**: SSMS → right-click the server → Properties → Security →
  "SQL Server and Windows Authentication mode", then restart the SQL Server service
- .NET 9 SDK
- Node.js 18 or later

## Setup

### 1. Database (SSMS, as administrator)

Run the scripts in order:

| Script | What it does |
|---|---|
| `01_schema.sql` | creates database `TicketHub`, tables, constraints, indexes, table type |
| `02_seed_data.sql` | 4 venues × 2,000 seats, 200 events, 20,003 users, ~72,000 bookings, ~290,000 tickets (≈ 10-30 s) |
| `03_logic.sql` | functions, procedures, trigger |
| `04_security.sql` | **first replace the password placeholder**, then run: creates login `TicketHubApp` with execute-only rights |
| `05_performance.sql` | (for the report) plans before/after, with Ctrl+M |
| `06_tests.sql` | (for the report) 19 automatic tests, PASS/FAIL table |
| `07_concurrency_demo.sql` | (for the demo) two windows booking the same seat |

### 2. API

```bash
cd api/TicketHub.Api
dotnet user-secrets set "ConnectionStrings:TicketHub" "Server=localhost;Database=TicketHub;User Id=TicketHubApp;Password=YOUR_PASSWORD;TrustServerCertificate=True"
dotnet run
```

- With SQL Server Express use `Server=localhost\SQLEXPRESS`.
- The secret is stored in your user profile, **not** in the project folder, so it never reaches git.
- The API listens on http://localhost:5080.

### 3. React app

```bash
cd web
npm install
npm run dev
```

Open http://localhost:5173. In development, Vite forwards `/api` to the C# API.

### Demo accounts

| Email | Password | Role |
|---|---|---|
| demo@tickethub.com | Demo123! | customer |
| demo2@tickethub.com | Demo123! | customer (second user for the concurrency demo) |
| staff@tickethub.com | Staff123! | staff |

## Tests

- **Database rules**: run `database/06_tests.sql` → one PASS/FAIL row per test (booking, taken seat,
  6-seat limit, past/cancelled event, someone else's booking, 24-hour rule, audit trigger,
  SQL injection, login, least privilege). It cleans up after itself.
- **Two users, same seat (SQL)**: follow `database/07_concurrency_demo.sql` with two SSMS windows.
- **Two users, same seat (through the API)**: with the API running, `node scripts/race-test.mjs`
  sends 10 simultaneous bookings for one seat → expected 1 × 201 and 9 × 409.
- **In the browser**: open the same event in two browsers (e.g. Chrome and Edge, logged in as demo and
  demo2), select the same seat in both, click Book in both. One gets the booking, the other the message
  "Sorry, one of these seats was just booked by another customer."

## Deploying on IIS

1. Install the **.NET 9 Hosting Bundle** on the server (adds the ASP.NET Core module to IIS).
2. Build the React app into the API's `wwwroot`: `cd web && npm run build`.
3. Publish the API: `cd api/TicketHub.Api && dotnet publish -c Release -o ../../publish`.
4. IIS Manager → Add Website → physical path = the `publish` folder. Application pool: **No Managed Code**.
5. Give the site its connection string **without putting it in the code**, either way:
   - **Recommended, no password at all**: run the optional block at the end of `04_security.sql`
     (login for `IIS APPPOOL\<pool name>`), then set the environment variable
     `ConnectionStrings__TicketHub = Server=.;Database=TicketHub;Integrated Security=True;TrustServerCertificate=True`
     (IIS Manager → site → Configuration Editor → `system.webServer/aspNetCore` → environmentVariables).
   - or the SQL login string from step 2 in the same environment variable.

React and the API are served by the same IIS site, so the browser talks to a single origin.

## Project structure

```
database/   SQL scripts 01-07 (create, data, logic, security, performance, tests, demo)
api/        C# ASP.NET Core Web API (ADO.NET, Microsoft.Data.SqlClient)
  Controllers/  Auth, Events, Bookings, Staff
  Data/         Db (connections + procedure commands), ErrorMapper (SQL error -> HTTP code)
  Models/       request and response records
web/        React app (Vite)
  src/pages/    Events, Event (seat map), Login, My bookings, Staff
scripts/    race-test.mjs (simultaneous bookings through the API)
```

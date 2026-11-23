USE TicketHub;
GO
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

DECLARE @EventID INT =
    (SELECT TOP 1 EventID FROM dbo.Event
     WHERE Status = 'Scheduled' AND EventDate > SYSDATETIME()
     ORDER BY EventDate);
DECLARE @CustomerID INT =
    (SELECT TOP 1 CustomerID FROM dbo.Booking
     GROUP BY CustomerID ORDER BY COUNT(*) DESC);
SELECT @EventID AS SampleEventID, @CustomerID AS SampleCustomerID;
GO

-- Query 1: seat map (before: forced scan / after: index)
DECLARE @EventID INT =
    (SELECT TOP 1 EventID FROM dbo.Event
     WHERE Status = 'Scheduled' AND EventDate > SYSDATETIME() ORDER BY EventDate);

SELECT s.SeatID, s.SeatRow, s.SeatNumber, s.Category,
       CASE WHEN t.TicketID IS NULL THEN 0 ELSE 1 END AS IsTaken
FROM dbo.Event e
JOIN dbo.Seat s ON s.VenueID = e.VenueID
LEFT JOIN dbo.Ticket t WITH (INDEX (PK_Ticket))
       ON t.EventID = e.EventID AND t.SeatID = s.SeatID AND t.Status = 'Active'
WHERE e.EventID = @EventID;

SELECT s.SeatID, s.SeatRow, s.SeatNumber, s.Category,
       CASE WHEN t.TicketID IS NULL THEN 0 ELSE 1 END AS IsTaken
FROM dbo.Event e
JOIN dbo.Seat s ON s.VenueID = e.VenueID
LEFT JOIN dbo.Ticket t
       ON t.EventID = e.EventID AND t.SeatID = s.SeatID AND t.Status = 'Active'
WHERE e.EventID = @EventID;
GO

-- Query 2: my bookings, before the indexes
DROP INDEX IF EXISTS IX_Booking_Customer ON dbo.Booking;
DROP INDEX IF EXISTS IX_Ticket_Booking   ON dbo.Ticket;
GO

DECLARE @CustomerID INT =
    (SELECT TOP 1 CustomerID FROM dbo.Booking GROUP BY CustomerID ORDER BY COUNT(*) DESC);

EXEC app.usp_GetCustomerBookings @CustomerID = @CustomerID;
GO

-- after the indexes
CREATE NONCLUSTERED INDEX IX_Booking_Customer
    ON dbo.Booking (CustomerID, EventID)
    INCLUDE (BookingDate, TotalAmount, Status);

CREATE NONCLUSTERED INDEX IX_Ticket_Booking
    ON dbo.Ticket (BookingID)
    INCLUDE (SeatID, Price, Status);
GO

DECLARE @CustomerID INT =
    (SELECT TOP 1 CustomerID FROM dbo.Booking GROUP BY CustomerID ORDER BY COUNT(*) DESC);

EXEC app.usp_GetCustomerBookings @CustomerID = @CustomerID;
GO

-- Query 3: monthly sales (before / after)
DECLARE @Year INT = YEAR(SYSDATETIME()) - 1;

SELECT MONTH(e.EventDate) AS [Month], COUNT(*) AS TicketsSold, SUM(t.Price) AS Revenue
FROM dbo.Ticket t WITH (INDEX (PK_Ticket))
JOIN dbo.Event e ON e.EventID = t.EventID
WHERE t.Status = 'Active'
  AND e.EventDate >= DATEFROMPARTS(@Year, 1, 1)
  AND e.EventDate <  DATEFROMPARTS(@Year + 1, 1, 1)
GROUP BY MONTH(e.EventDate);

SELECT MONTH(e.EventDate) AS [Month], COUNT(*) AS TicketsSold, SUM(t.Price) AS Revenue
FROM dbo.Ticket t
JOIN dbo.Event e ON e.EventID = t.EventID
WHERE t.Status = 'Active'
  AND e.EventDate >= DATEFROMPARTS(@Year, 1, 1)
  AND e.EventDate <  DATEFROMPARTS(@Year + 1, 1, 1)
GROUP BY MONTH(e.EventDate);
GO

-- scalar function vs CROSS APPLY
SELECT EventID, Title, app.fn_SeatsLeft(EventID) AS SeatsLeft
FROM dbo.Event
WHERE Status = 'Scheduled' AND EventDate > SYSDATETIME();

EXEC app.usp_GetUpcomingEvents;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

USE TicketHub;
GO

-- setup (run once)
DECLARE @DemoEvent INT = (SELECT EventID FROM dbo.Event WHERE Title = N'Concurrency Demo');
IF @DemoEvent IS NOT NULL
BEGIN   -- reset the demo from a previous run
    DELETE a FROM dbo.BookingAudit a WHERE a.EventID = @DemoEvent;
    DELETE FROM dbo.Ticket  WHERE EventID = @DemoEvent;
    DELETE FROM dbo.Booking WHERE EventID = @DemoEvent;
END
ELSE
BEGIN
    DECLARE @Venue INT = 1, @Title NVARCHAR(150) = N'Concurrency Demo',
            @Date DATETIME2(0) = DATEADD(DAY, 30, SYSDATETIME()),
            @Std DECIMAL(10,2) = 40, @Vip DECIMAL(10,2) = 80;
    EXEC app.usp_CreateEvent @Venue, @Title, @Date, @Std, @Vip, @DemoEvent OUTPUT;
END
SELECT @DemoEvent AS DemoEventID;
GO

-- WINDOW 1, step 1: book and keep the transaction open
DECLARE @Event INT = (SELECT EventID FROM dbo.Event WHERE Title = N'Concurrency Demo');
DECLARE @Seat  INT = (SELECT s.SeatID FROM dbo.Seat s JOIN dbo.Event e ON e.VenueID = s.VenueID
                      WHERE e.EventID = @Event AND s.SeatRow = 1 AND s.SeatNumber = 1);
DECLARE @Cust  INT = (SELECT CustomerID FROM dbo.Customer WHERE Email = N'demo@tickethub.com');
DECLARE @Seats app.SeatIdList, @BookingA INT;
INSERT INTO @Seats VALUES (@Seat);

BEGIN TRANSACTION;                 -- outer transaction = user A is "slow"
EXEC app.usp_BookSeats @Cust, @Event, @Seats, @BookingA OUTPUT;
SELECT @BookingA AS BookingA, @@TRANCOUNT AS OpenTransactions;   -- 1 = still open

GO

-- WINDOW 1, step 2: run after starting window 2
COMMIT TRANSACTION;
GO

-- WINDOW 2: run while window 1 is still open
USE TicketHub;
GO
DECLARE @Event INT = (SELECT EventID FROM dbo.Event WHERE Title = N'Concurrency Demo');
DECLARE @Seat  INT = (SELECT s.SeatID FROM dbo.Seat s JOIN dbo.Event e ON e.VenueID = s.VenueID
                      WHERE e.EventID = @Event AND s.SeatRow = 1 AND s.SeatNumber = 1);
DECLARE @Cust  INT = (SELECT CustomerID FROM dbo.Customer WHERE Email = N'demo2@tickethub.com');
DECLARE @Seats app.SeatIdList, @BookingB INT;
INSERT INTO @Seats VALUES (@Seat);

EXEC app.usp_BookSeats @Cust, @Event, @Seats, @BookingB OUTPUT;   -- waits for window 1
SELECT @BookingB AS BookingB;
GO

-- result
SELECT t.TicketID, t.BookingID, c.Email, t.Status
FROM dbo.Ticket t
JOIN dbo.Booking  b ON b.BookingID  = t.BookingID
JOIN dbo.Customer c ON c.CustomerID = b.CustomerID
JOIN dbo.Event    e ON e.EventID    = t.EventID
WHERE e.Title = N'Concurrency Demo';
GO

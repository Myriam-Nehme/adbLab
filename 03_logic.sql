USE TicketHub;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER FUNCTION app.fn_SeatsLeft (@EventID INT)
RETURNS INT
AS
BEGIN
    DECLARE @Capacity INT, @Sold INT;

    SELECT @Capacity = COUNT(*)
    FROM dbo.Seat s
    JOIN dbo.Event e ON e.VenueID = s.VenueID
    WHERE e.EventID = @EventID;

    SELECT @Sold = COUNT(*)
    FROM dbo.Ticket
    WHERE EventID = @EventID AND Status = 'Active';

    RETURN @Capacity - @Sold;
END
GO

CREATE OR ALTER FUNCTION app.fn_EventSales (@EventID INT)
RETURNS TABLE
AS
RETURN
    SELECT s.Category,
           COUNT(*)     AS TicketsSold,
           SUM(t.Price) AS Revenue
    FROM dbo.Ticket t
    JOIN dbo.Seat   s ON s.SeatID = t.SeatID
    WHERE t.EventID = @EventID
      AND t.Status  = 'Active'
    GROUP BY s.Category;
GO

CREATE OR ALTER TRIGGER dbo.trg_Booking_Audit
ON dbo.Booking
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.BookingAudit (BookingID, CustomerID, EventID, Action, Amount)
    SELECT i.BookingID, i.CustomerID, i.EventID, 'Booked', i.TotalAmount
    FROM inserted i
    WHERE NOT EXISTS (SELECT 1 FROM deleted d WHERE d.BookingID = i.BookingID);

    INSERT INTO dbo.BookingAudit (BookingID, CustomerID, EventID, Action, Amount)
    SELECT i.BookingID, i.CustomerID, i.EventID, 'Cancelled', i.TotalAmount
    FROM inserted i
    JOIN deleted  d ON d.BookingID = i.BookingID
    WHERE d.Status = 'Active' AND i.Status = 'Cancelled';
END
GO

CREATE OR ALTER PROCEDURE app.usp_GetVenues
AS
BEGIN
    SET NOCOUNT ON;
    SELECT VenueID, Name, City FROM dbo.Venue ORDER BY Name;
END
GO

CREATE OR ALTER PROCEDURE app.usp_GetUpcomingEvents
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.EventID, e.Title, e.EventDate, e.StandardPrice, e.VipPrice,
           v.Name AS VenueName, v.City,
           cap.Capacity,
           cap.Capacity - sold.Sold AS SeatsLeft
    FROM dbo.Event e
    JOIN dbo.Venue v ON v.VenueID = e.VenueID
    CROSS APPLY (SELECT COUNT(*) AS Capacity FROM dbo.Seat s WHERE s.VenueID = e.VenueID) cap
    CROSS APPLY (SELECT COUNT(*) AS Sold
                 FROM dbo.Ticket t
                 WHERE t.EventID = e.EventID AND t.Status = 'Active') sold
    WHERE e.Status = 'Scheduled'
      AND e.EventDate > SYSDATETIME()
    ORDER BY e.EventDate;
END
GO

CREATE OR ALTER PROCEDURE app.usp_GetEvent
    @EventID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Event WHERE EventID = @EventID)
        THROW 50002, N'Event not found.', 1;

    SELECT e.EventID, e.Title, e.EventDate, e.Status, e.StandardPrice, e.VipPrice,
           v.VenueID, v.Name AS VenueName, v.City,
           app.fn_SeatsLeft(e.EventID) AS SeatsLeft
    FROM dbo.Event e
    JOIN dbo.Venue v ON v.VenueID = e.VenueID
    WHERE e.EventID = @EventID;
END
GO

CREATE OR ALTER PROCEDURE app.usp_GetEventSeats
    @EventID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Event WHERE EventID = @EventID)
        THROW 50002, N'Event not found.', 1;

    SELECT s.SeatID, s.SeatRow, s.SeatNumber, s.Category,
           CAST(CASE WHEN t.TicketID IS NULL THEN 0 ELSE 1 END AS BIT) AS IsTaken
    FROM dbo.Event e
    JOIN dbo.Seat s ON s.VenueID = e.VenueID
    LEFT JOIN dbo.Ticket t
           ON t.EventID = e.EventID
          AND t.SeatID  = s.SeatID
          AND t.Status  = 'Active'
    WHERE e.EventID = @EventID
    ORDER BY s.SeatRow, s.SeatNumber;
END
GO

CREATE OR ALTER PROCEDURE app.usp_Login
    @Email    NVARCHAR(255),
    @Password NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CustomerID, FullName, Email, Role
    FROM dbo.Customer
    WHERE Email = LTRIM(RTRIM(@Email))
      AND PasswordHash = HASHBYTES('SHA2_256', PasswordSalt + CAST(@Password AS VARBINARY(MAX)));
END
GO

CREATE OR ALTER PROCEDURE app.usp_GetCustomerBookings
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT b.BookingID, b.BookingDate, b.TotalAmount, b.Status,
           e.EventID, e.Title, e.EventDate, v.Name AS VenueName,
           COUNT(*) AS SeatCount,
           STRING_AGG(CONCAT(N'Row ', s.SeatRow, N' Seat ', s.SeatNumber), N', ')
               WITHIN GROUP (ORDER BY s.SeatRow, s.SeatNumber) AS Seats,
           CAST(CASE WHEN b.Status = 'Active'
                      AND e.EventDate > DATEADD(HOUR, 24, SYSDATETIME())
                     THEN 1 ELSE 0 END AS BIT) AS CanCancel
    FROM dbo.Booking b
    JOIN dbo.Event  e ON e.EventID   = b.EventID
    JOIN dbo.Venue  v ON v.VenueID   = e.VenueID
    JOIN dbo.Ticket t ON t.BookingID = b.BookingID
    JOIN dbo.Seat   s ON s.SeatID    = t.SeatID
    WHERE b.CustomerID = @CustomerID
    GROUP BY b.BookingID, b.BookingDate, b.TotalAmount, b.Status,
             e.EventID, e.Title, e.EventDate, v.Name
    ORDER BY e.EventDate DESC;
END
GO

CREATE OR ALTER PROCEDURE app.usp_SalesReport
    @FromDate DATE,
    @ToDate   DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL OR @ToDate IS NULL OR @FromDate > @ToDate
        THROW 50001, N'Please give a valid date range.', 1;

    SELECT e.EventID, e.Title, e.EventDate, e.Status, v.Name AS VenueName,
           sold.TicketsSold, sold.Revenue, cap.Capacity,
           CAST(100.0 * sold.TicketsSold / cap.Capacity AS DECIMAL(5,1)) AS FillRatePct
    FROM dbo.Event e
    JOIN dbo.Venue v ON v.VenueID = e.VenueID
    CROSS APPLY (SELECT COUNT(*) AS TicketsSold, ISNULL(SUM(t.Price), 0) AS Revenue
                 FROM dbo.Ticket t
                 WHERE t.EventID = e.EventID AND t.Status = 'Active') sold
    CROSS APPLY (SELECT COUNT(*) AS Capacity FROM dbo.Seat s WHERE s.VenueID = e.VenueID) cap
    WHERE e.EventDate >= @FromDate
      AND e.EventDate <  DATEADD(DAY, 1, @ToDate)          -- SARGable date range
    ORDER BY e.EventDate;
END
GO

CREATE OR ALTER PROCEDURE app.usp_MonthlySales
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @Year IS NULL OR @Year < 2000 OR @Year > 2100
        THROW 50001, N'Please give a valid year.', 1;

    SELECT MONTH(e.EventDate) AS [Month],
           COUNT(*)           AS TicketsSold,
           SUM(t.Price)       AS Revenue,
           SUM(SUM(t.Price)) OVER (ORDER BY MONTH(e.EventDate)
                                   ROWS UNBOUNDED PRECEDING) AS RunningRevenue
    FROM dbo.Ticket t
    JOIN dbo.Event  e ON e.EventID = t.EventID
    WHERE t.Status = 'Active'
      AND e.EventDate >= DATEFROMPARTS(@Year, 1, 1)
      AND e.EventDate <  DATEFROMPARTS(@Year + 1, 1, 1)
    GROUP BY MONTH(e.EventDate)
    ORDER BY [Month];
END
GO

CREATE OR ALTER PROCEDURE app.usp_GetEventSales
    @EventID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Event WHERE EventID = @EventID)
        THROW 50002, N'Event not found.', 1;

    SELECT Category, TicketsSold, Revenue
    FROM app.fn_EventSales(@EventID)
    ORDER BY Category;
END
GO

CREATE OR ALTER PROCEDURE app.usp_RegisterCustomer
    @FullName   NVARCHAR(100),
    @Email      NVARCHAR(255),
    @Password   NVARCHAR(100),
    @CustomerID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @FullName = LTRIM(RTRIM(@FullName));
    SET @Email    = LTRIM(RTRIM(@Email));

    IF @FullName IS NULL OR @FullName = N''
        THROW 50001, N'Please enter your name.', 1;
    IF @Password IS NULL OR LEN(@Password) < 8
        THROW 50001, N'The password must have at least 8 characters.', 1;

    DECLARE @Salt VARBINARY(16) = CRYPT_GEN_RANDOM(16);          -- new random salt for this user

    BEGIN TRY
        INSERT INTO dbo.Customer (FullName, Email, PasswordSalt, PasswordHash)
        VALUES (@FullName, @Email, @Salt,
                HASHBYTES('SHA2_256', @Salt + CAST(@Password AS VARBINARY(MAX))));
        SET @CustomerID = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)          -- UQ_Customer_Email
            THROW 50003, N'An account with this email already exists.', 1;
        IF ERROR_NUMBER() = 547                    -- CK_Customer_Email
            THROW 50001, N'Please enter a valid email address.', 1;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE app.usp_BookSeats
    @CustomerID INT,
    @EventID    INT,
    @SeatIds    app.SeatIdList READONLY,
    @BookingID  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;              -- any error dooms the transaction

    DECLARE @SeatCount INT = (SELECT COUNT(*) FROM @SeatIds);
    IF @SeatCount = 0 THROW 50001, N'Please choose at least one seat.', 1;
    IF @SeatCount > 6 THROW 50004, N'You can book at most 6 seats per event.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM dbo.Customer WITH (UPDLOCK, HOLDLOCK)
                       WHERE CustomerID = @CustomerID)
            THROW 50002, N'Customer not found.', 1;

        DECLARE @VenueID INT, @EventDate DATETIME2(0), @EventStatus VARCHAR(10),
                @Std DECIMAL(10,2), @Vip DECIMAL(10,2);

        SELECT @VenueID = VenueID, @EventDate = EventDate, @EventStatus = Status,
               @Std = StandardPrice, @Vip = VipPrice
        FROM dbo.Event
        WHERE EventID = @EventID;

        IF @VenueID IS NULL               THROW 50002, N'Event not found.', 1;
        IF @EventStatus <> 'Scheduled'    THROW 50004, N'This event has been cancelled.', 1;
        IF @EventDate <= SYSDATETIME()    THROW 50004, N'This event has already taken place.', 1;

        IF EXISTS (SELECT 1
                   FROM @SeatIds r
                   LEFT JOIN dbo.Seat s ON s.SeatID = r.SeatID AND s.VenueID = @VenueID
                   WHERE s.SeatID IS NULL)
            THROW 50001, N'One or more seats do not belong to this venue.', 1;

        DECLARE @AlreadyBooked INT =
            (SELECT COUNT(*)
             FROM dbo.Ticket t
             JOIN dbo.Booking b ON b.BookingID = t.BookingID
             WHERE b.CustomerID = @CustomerID
               AND t.EventID    = @EventID
               AND t.Status     = 'Active');

        IF @AlreadyBooked + @SeatCount > 6
        BEGIN
            DECLARE @Msg NVARCHAR(200) =
                CONCAT(N'You already have ', @AlreadyBooked,
                       N' seat(s) for this event. The limit is 6 per customer.');
            THROW 50004, @Msg, 1;
        END

        IF EXISTS (SELECT 1
                   FROM dbo.Ticket t
                   JOIN @SeatIds r ON r.SeatID = t.SeatID
                   WHERE t.EventID = @EventID AND t.Status = 'Active')
            THROW 50003, N'One or more of the selected seats are already taken.', 1;

        INSERT INTO dbo.Booking (CustomerID, EventID, TotalAmount)
        SELECT @CustomerID, @EventID,
               SUM(CASE s.Category WHEN 'VIP' THEN @Vip ELSE @Std END)
        FROM @SeatIds r
        JOIN dbo.Seat s ON s.SeatID = r.SeatID;

        SET @BookingID = SCOPE_IDENTITY();

        INSERT INTO dbo.Ticket (BookingID, EventID, SeatID, Price)
        SELECT @BookingID, @EventID, s.SeatID,
               CASE s.Category WHEN 'VIP' THEN @Vip ELSE @Std END
        FROM @SeatIds r
        JOIN dbo.Seat s ON s.SeatID = r.SeatID
        ORDER BY s.SeatID;               -- same order for everyone: fewer deadlocks

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50003, N'Sorry, one of these seats was just booked by another customer.', 1;
        IF ERROR_NUMBER() = 1205                   -- chosen as deadlock victim
            THROW 50003, N'These seats are being booked by someone else right now. Please try again.', 1;

        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE app.usp_CancelBooking
    @BookingID  INT,
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Owner INT, @Status VARCHAR(10), @EventDate DATETIME2(0);

        SELECT @Owner = b.CustomerID, @Status = b.Status, @EventDate = e.EventDate
        FROM dbo.Booking b WITH (UPDLOCK)          -- nobody else changes it until COMMIT
        JOIN dbo.Event e ON e.EventID = b.EventID
        WHERE b.BookingID = @BookingID;

        IF @Owner IS NULL OR @Owner <> @CustomerID
            THROW 50002, N'Booking not found.', 1;
        IF @Status = 'Cancelled'
            THROW 50004, N'This booking is already cancelled.', 1;
        IF @EventDate <= DATEADD(HOUR, 24, SYSDATETIME())
            THROW 50004, N'Bookings can only be cancelled up to 24 hours before the event.', 1;

        UPDATE dbo.Ticket  SET Status = 'Cancelled' WHERE BookingID = @BookingID AND Status = 'Active';
        UPDATE dbo.Booking SET Status = 'Cancelled' WHERE BookingID = @BookingID;   -- fires the trigger

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE app.usp_CreateEvent
    @VenueID       INT,
    @Title         NVARCHAR(150),
    @EventDate     DATETIME2(0),
    @StandardPrice DECIMAL(10,2),
    @VipPrice      DECIMAL(10,2),
    @EventID       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Title = LTRIM(RTRIM(@Title));

    IF @Title IS NULL OR @Title = N''
        THROW 50001, N'Please enter a title.', 1;
    IF @EventDate IS NULL OR @EventDate <= SYSDATETIME()
        THROW 50004, N'The event date must be in the future.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Venue WHERE VenueID = @VenueID)
        THROW 50002, N'Venue not found.', 1;

    BEGIN TRY
        INSERT INTO dbo.Event (VenueID, Title, EventDate, StandardPrice, VipPrice)
        VALUES (@VenueID, @Title, @EventDate, @StandardPrice, @VipPrice);
        SET @EventID = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 547                    -- CK_Event_Standard / CK_Event_Vip
            THROW 50001, N'Prices must be positive and the VIP price cannot be lower than the Standard price.', 1;
        THROW;
    END CATCH
END
GO

PRINT 'Functions, procedures and trigger created.';

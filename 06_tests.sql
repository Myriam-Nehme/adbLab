USE TicketHub;
GO
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#Results') IS NOT NULL DROP TABLE #Results;
CREATE TABLE #Results
(
    TestNo   INT,
    Test     NVARCHAR(200),
    Expected NVARCHAR(100),
    Outcome  NVARCHAR(400),
    Result   VARCHAR(4)
);

DELETE a FROM dbo.BookingAudit a JOIN dbo.Customer c ON c.CustomerID = a.CustomerID WHERE c.Email LIKE N'test.%@tickethub.test';
DELETE t FROM dbo.Ticket  t JOIN dbo.Booking b ON b.BookingID = t.BookingID JOIN dbo.Customer c ON c.CustomerID = b.CustomerID WHERE c.Email LIKE N'test.%@tickethub.test';
DELETE b FROM dbo.Booking b JOIN dbo.Customer c ON c.CustomerID = b.CustomerID WHERE c.Email LIKE N'test.%@tickethub.test';
DELETE FROM dbo.Event    WHERE Title = N'TEST event starting soon';
DELETE FROM dbo.Customer WHERE Email LIKE N'test.%@tickethub.test';

DECLARE @Cust1 INT, @Cust2 INT, @Dummy INT,
        @Event INT, @PastEvent INT, @CancelledEvent INT, @SoonEvent INT,
        @OtherVenueSeat INT, @Booking1 INT, @Booking2 INT, @BookingSoon INT,
        @SoonDate DATETIME2(0) = DATEADD(HOUR, 3, SYSDATETIME()),
        @Std DECIMAL(10,2) = 30, @Vip DECIMAL(10,2) = 60, @Venue1 INT = 1,
        @Name NVARCHAR(100), @Email NVARCHAR(255), @Pwd NVARCHAR(100) = N'Test1234!';
DECLARE @Seats app.SeatIdList;

SET @Name = N'Test One'; SET @Email = N'test.one@tickethub.test';
EXEC app.usp_RegisterCustomer @Name, @Email, @Pwd, @Cust1 OUTPUT;
SET @Name = N'Test Two'; SET @Email = N'test.two@tickethub.test';
EXEC app.usp_RegisterCustomer @Name, @Email, @Pwd, @Cust2 OUTPUT;

SELECT TOP 1 @Event = EventID FROM dbo.Event
WHERE Status = 'Scheduled' AND EventDate > DATEADD(DAY, 2, SYSDATETIME()) ORDER BY EventDate;

SELECT TOP 1 @PastEvent = EventID FROM dbo.Event
WHERE Status = 'Scheduled' AND EventDate < SYSDATETIME() ORDER BY EventDate DESC;

SELECT TOP 1 @CancelledEvent = EventID FROM dbo.Event
WHERE Status = 'Cancelled' AND EventDate > SYSDATETIME();

IF OBJECT_ID('tempdb..#Free') IS NOT NULL DROP TABLE #Free;
SELECT TOP (8) ROW_NUMBER() OVER (ORDER BY s.SeatID) AS k, s.SeatID
INTO #Free
FROM dbo.Seat s
JOIN dbo.Event e ON e.VenueID = s.VenueID
WHERE e.EventID = @Event
  AND NOT EXISTS (SELECT 1 FROM dbo.Ticket t
                  WHERE t.EventID = @Event AND t.SeatID = s.SeatID AND t.Status = 'Active')
ORDER BY s.SeatID;

SELECT TOP 1 @OtherVenueSeat = SeatID FROM dbo.Seat
WHERE VenueID <> (SELECT VenueID FROM dbo.Event WHERE EventID = @Event);

DELETE FROM @Seats; INSERT INTO @Seats SELECT SeatID FROM #Free WHERE k IN (1, 2);
BEGIN TRY
    EXEC app.usp_BookSeats @Cust1, @Event, @Seats, @Booking1 OUTPUT;
    INSERT INTO #Results
    SELECT 1, N'Book 2 free seats', N'Booking with 2 tickets',
           CONCAT(N'BookingID ', @Booking1, N', tickets: ', COUNT(*)),
           CASE WHEN COUNT(*) = 2 THEN 'PASS' ELSE 'FAIL' END
    FROM dbo.Ticket WHERE BookingID = @Booking1;
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (1, N'Book 2 free seats', N'Booking with 2 tickets', ERROR_MESSAGE(), 'FAIL');
END CATCH;

DELETE FROM @Seats; INSERT INTO @Seats SELECT SeatID FROM #Free WHERE k = 2;
BEGIN TRY
    EXEC app.usp_BookSeats @Cust2, @Event, @Seats, @Dummy OUTPUT;
    INSERT INTO #Results VALUES (2, N'Book a seat already sold', N'Error 50003', N'No error', 'FAIL');
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (2, N'Book a seat already sold', N'Error 50003',
        CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()), CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END);
END CATCH;

DELETE FROM @Seats; INSERT INTO @Seats SELECT SeatID FROM #Free WHERE k BETWEEN 3 AND 7;
BEGIN TRY
    EXEC app.usp_BookSeats @Cust1, @Event, @Seats, @Dummy OUTPUT;
    INSERT INTO #Results VALUES (3, N'Exceed 6 seats per customer (2 + 5)', N'Error 50004', N'No error', 'FAIL');
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (3, N'Exceed 6 seats per customer (2 + 5)', N'Error 50004',
        CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()), CASE WHEN ERROR_NUMBER() = 50004 THEN 'PASS' ELSE 'FAIL' END);
END CATCH;

DELETE FROM @Seats; INSERT INTO @Seats SELECT SeatID FROM #Free WHERE k BETWEEN 2 AND 8;
BEGIN TRY
    EXEC app.usp_BookSeats @Cust2, @Event, @Seats, @Dummy OUTPUT;
    INSERT INTO #Results VALUES (4, N'7 seats in one booking', N'Error 50004', N'No error', 'FAIL');
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (4, N'7 seats in one booking', N'Error 50004',
        CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()), CASE WHEN ERROR_NUMBER() = 50004 THEN 'PASS' ELSE 'FAIL' END);
END CATCH;

DELETE FROM @Seats; INSERT INTO @Seats VALUES (@OtherVenueSeat);
BEGIN TRY
    EXEC app.usp_BookSeats @Cust2, @Event, @Seats, @Dummy OUTPUT;
    INSERT INTO #Results VALUES (5, N'Seat of another venue', N'Error 50001', N'No error', 'FAIL');
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (5, N'Seat of another venue', N'Error 50001',
        CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()), CASE WHEN ERROR_NUMBER() = 50001 THEN 'PASS' ELSE 'FAIL' END);
END CATCH;

DELETE FROM @Seats; INSERT INTO @Seats SELECT SeatID FROM #Free WHERE k = 8;
BEGIN TRY
    EXEC app.usp_BookSeats @Cust2, @PastEvent, @Seats, @Dummy OUTPUT;
    INSERT INTO #Results VALUES (6, N'Book a past event', N'Error 50004', N'No error', 'FAIL');
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (6, N'Book a past event', N'Error 50004',
        CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()), CASE WHEN ERROR_NUMBER() = 50004 THEN 'PASS' ELSE 'FAIL' END);
END CATCH;

BEGIN TRY
    EXEC app.usp_BookSeats @Cust2, @CancelledEvent, @Seats, @Dummy OUTPUT;
    INSERT INTO #Results VALUES (7, N'Book a cancelled event', N'Error 50004', N'No error', 'FAIL');
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (7, N'Book a cancelled event', N'Error 50004',
        CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()), CASE WHEN ERROR_NUMBER() = 50004 THEN 'PASS' ELSE 'FAIL' END);
END CATCH;

BEGIN TRY
    EXEC app.usp_CancelBooking @Booking1, @Cust2;
    INSERT INTO #Results VALUES (8, N'Cancel another customer''s booking', N'Error 50002', N'No error', 'FAIL');
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (8, N'Cancel another customer''s booking', N'Error 50002',
        CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()), CASE WHEN ERROR_NUMBER() = 50002 THEN 'PASS' ELSE 'FAIL' END);
END CATCH;

BEGIN TRY
    EXEC app.usp_CancelBooking @Booking1, @Cust1;
    INSERT INTO #Results
    SELECT 9, N'Cancel own booking (trigger writes audit)', N'Cancelled + audit row',
           CONCAT(N'Booking: ', (SELECT Status FROM dbo.Booking WHERE BookingID = @Booking1),
                  N', active tickets: ', (SELECT COUNT(*) FROM dbo.Ticket WHERE BookingID = @Booking1 AND Status = 'Active'),
                  N', audit rows: ', (SELECT COUNT(*) FROM dbo.BookingAudit WHERE BookingID = @Booking1 AND Action = 'Cancelled')),
           CASE WHEN (SELECT Status FROM dbo.Booking WHERE BookingID = @Booking1) = 'Cancelled'
                 AND (SELECT COUNT(*) FROM dbo.Ticket WHERE BookingID = @Booking1 AND Status = 'Active') = 0
                 AND (SELECT COUNT(*) FROM dbo.BookingAudit WHERE BookingID = @Booking1 AND Action = 'Cancelled') = 1
                THEN 'PASS' ELSE 'FAIL' END;
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (9, N'Cancel own booking (trigger writes audit)', N'Cancelled + audit row', ERROR_MESSAGE(), 'FAIL');
END CATCH;

DELETE FROM @Seats; INSERT INTO @Seats SELECT SeatID FROM #Free WHERE k = 2;
BEGIN TRY
    EXEC app.usp_BookSeats @Cust2, @Event, @Seats, @Booking2 OUTPUT;
    INSERT INTO #Results VALUES (10, N'Rebook a seat freed by a cancellation', N'Success',
        CONCAT(N'BookingID ', @Booking2), 'PASS');
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (10, N'Rebook a seat freed by a cancellation', N'Success', ERROR_MESSAGE(), 'FAIL');
END CATCH;

BEGIN TRY
    SET @Name = N'TEST event starting soon';
    EXEC app.usp_CreateEvent @Venue1, @Name, @SoonDate, @Std, @Vip, @SoonEvent OUTPUT;
    DELETE FROM @Seats;
    INSERT INTO @Seats SELECT TOP 1 SeatID FROM dbo.Seat WHERE VenueID = @Venue1 ORDER BY SeatID;
    EXEC app.usp_BookSeats @Cust1, @SoonEvent, @Seats, @BookingSoon OUTPUT;
    EXEC app.usp_CancelBooking @BookingSoon, @Cust1;
    INSERT INTO #Results VALUES (11, N'Cancel 3 hours before the event', N'Error 50004', N'No error', 'FAIL');
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (11, N'Cancel 3 hours before the event', N'Error 50004',
        CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()), CASE WHEN ERROR_NUMBER() = 50004 THEN 'PASS' ELSE 'FAIL' END);
END CATCH;

BEGIN TRY
    SET @Name = N'Copy'; SET @Email = N'test.one@tickethub.test';
    EXEC app.usp_RegisterCustomer @Name, @Email, @Pwd, @Dummy OUTPUT;
    INSERT INTO #Results VALUES (12, N'Register an email that already exists', N'Error 50003', N'No error', 'FAIL');
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (12, N'Register an email that already exists', N'Error 50003',
        CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()), CASE WHEN ERROR_NUMBER() = 50003 THEN 'PASS' ELSE 'FAIL' END);
END CATCH;

BEGIN TRY
    SET @Name = N'Bad'; SET @Email = N'not-an-email';
    EXEC app.usp_RegisterCustomer @Name, @Email, @Pwd, @Dummy OUTPUT;
    INSERT INTO #Results VALUES (13, N'Register an invalid email', N'Error 50001', N'No error', 'FAIL');
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (13, N'Register an invalid email', N'Error 50001',
        CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()), CASE WHEN ERROR_NUMBER() = 50001 THEN 'PASS' ELSE 'FAIL' END);
END CATCH;

DECLARE @Found TABLE (CustomerID INT, FullName NVARCHAR(100), Email NVARCHAR(255), Role VARCHAR(10));
SET @Email = N''' OR 1=1 --';
INSERT INTO @Found EXEC app.usp_Login @Email, @Pwd;
INSERT INTO #Results
SELECT 14, N'Login with email = '' OR 1=1 -- (SQL injection)', N'0 rows',
       CONCAT(COUNT(*), N' rows'), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM @Found;

DELETE FROM @Found;
SET @Email = N'test.one@tickethub.test';
INSERT INTO @Found EXEC app.usp_Login @Email, @Pwd;
INSERT INTO #Results
SELECT 17, N'Login with the right password', N'1 row',
       CONCAT(COUNT(*), N' row(s)'), CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM @Found;

DELETE FROM @Found;
SET @Name = N'Wrong-password';
INSERT INTO @Found EXEC app.usp_Login @Email, @Name;
INSERT INTO #Results
SELECT 18, N'Login with a wrong password', N'0 rows',
       CONCAT(COUNT(*), N' row(s)'), CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM @Found;

DECLARE @Short NVARCHAR(100) = N'abc';
BEGIN TRY
    SET @Name = N'Short'; SET @Email = N'test.short@tickethub.test';
    EXEC app.usp_RegisterCustomer @Name, @Email, @Short, @Dummy OUTPUT;
    INSERT INTO #Results VALUES (19, N'Register with a 3-character password', N'Error 50001', N'No error', 'FAIL');
END TRY
BEGIN CATCH
    INSERT INTO #Results VALUES (19, N'Register with a 3-character password', N'Error 50001',
        CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()), CASE WHEN ERROR_NUMBER() = 50001 THEN 'PASS' ELSE 'FAIL' END);
END CATCH;

IF USER_ID(N'TicketHubApp') IS NOT NULL
BEGIN
    DECLARE @Venues TABLE (VenueID INT, Name NVARCHAR(100), City NVARCHAR(50));

    EXECUTE AS USER = N'TicketHubApp';            -- act as the application

    BEGIN TRY
        SELECT TOP 1 @Dummy = TicketID FROM dbo.Ticket;
        INSERT INTO #Results VALUES (15, N'App login reads dbo.Ticket directly', N'Error 229 (denied)', N'Allowed!', 'FAIL');
    END TRY
    BEGIN CATCH
        INSERT INTO #Results VALUES (15, N'App login reads dbo.Ticket directly', N'Error 229 (denied)',
            CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()), CASE WHEN ERROR_NUMBER() = 229 THEN 'PASS' ELSE 'FAIL' END);
    END CATCH;

    BEGIN TRY
        INSERT INTO @Venues EXEC app.usp_GetVenues;
        INSERT INTO #Results
        SELECT 16, N'App login executes a procedure', N'Allowed',
               CONCAT(COUNT(*), N' venues returned'), CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END
        FROM @Venues;
    END TRY
    BEGIN CATCH
        INSERT INTO #Results VALUES (16, N'App login executes a procedure', N'Allowed', ERROR_MESSAGE(), 'FAIL');
    END CATCH;

    REVERT;                                       -- back to the administrator
END
ELSE
    INSERT INTO #Results VALUES (15, N'Security tests', N'-', N'Run 04_security.sql first', 'SKIP');

SELECT TestNo, Test, Expected, Outcome, Result FROM #Results ORDER BY TestNo;

DELETE a FROM dbo.BookingAudit a JOIN dbo.Customer c ON c.CustomerID = a.CustomerID WHERE c.Email LIKE N'test.%@tickethub.test';
DELETE t FROM dbo.Ticket  t JOIN dbo.Booking b ON b.BookingID = t.BookingID JOIN dbo.Customer c ON c.CustomerID = b.CustomerID WHERE c.Email LIKE N'test.%@tickethub.test';
DELETE b FROM dbo.Booking b JOIN dbo.Customer c ON c.CustomerID = b.CustomerID WHERE c.Email LIKE N'test.%@tickethub.test';
DELETE FROM dbo.Event    WHERE Title = N'TEST event starting soon';
DELETE FROM dbo.Customer WHERE Email LIKE N'test.%@tickethub.test';
GO

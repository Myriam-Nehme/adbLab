USE TicketHub;
GO
SET NOCOUNT ON;

DECLARE @Now           DATETIME2(0) = SYSDATETIME();
DECLARE @Today         DATE         = CAST(@Now AS DATE);
DECLARE @CustomerCount INT          = 20000;

IF OBJECT_ID('tempdb..#Numbers') IS NOT NULL DROP TABLE #Numbers;
SELECT TOP (20000) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS INT) AS n   -- INT: DATEADD refuses BIGINT
INTO #Numbers
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

INSERT INTO dbo.Venue (Name, City)
VALUES (N'Beirut Hall',     N'Beirut'),
       (N'Byblos Arena',    N'Byblos'),
       (N'Tripoli Theatre', N'Tripoli'),
       (N'Saida Stage',     N'Saida');

INSERT INTO dbo.Seat (VenueID, SeatRow, SeatNumber, Category)
SELECT v.VenueID, r.n, s.n,
       CASE WHEN r.n <= 6 THEN 'VIP' ELSE 'Standard' END
FROM dbo.Venue v
CROSS JOIN (SELECT n FROM #Numbers WHERE n <= 40) r
CROSS JOIN (SELECT n FROM #Numbers WHERE n <= 50) s;

INSERT INTO dbo.Event (VenueID, Title, EventDate, StandardPrice, VipPrice, Status)
SELECT ((n - 1) % 4) + 1,
       CHOOSE(((n - 1) % 10) + 1,
              N'Jazz Night', N'Rock Live', N'Classical Evening', N'Stand-up Comedy',
              N'Oriental Music Night', N'Theatre: Hamlet', N'Pop Concert',
              N'Fairuz Tribute', N'Electronic Night', N'Kids Show')
           + N' #' + CAST(n AS NVARCHAR(10)),
       DATEADD(HOUR, 20, CAST(DATEADD(DAY, (n - 1) * 4 - 480, @Today) AS DATETIME2(0))),
       25 + ((n - 1) % 6) * 5,
       (25 + ((n - 1) % 6) * 5) * 2,
       CASE WHEN n % 50 = 0 THEN 'Cancelled' ELSE 'Scheduled' END
FROM #Numbers
WHERE n <= 200;

DECLARE @First TABLE (i INT PRIMARY KEY, Name NVARCHAR(30));
DECLARE @Last  TABLE (i INT PRIMARY KEY, Name NVARCHAR(30));

INSERT INTO @First (i, Name) VALUES
 (0,N'Ali'),(1,N'Maya'),(2,N'Omar'),(3,N'Lea'),(4,N'Karim'),(5,N'Nour'),(6,N'Rami'),(7,N'Sara'),
 (8,N'Hadi'),(9,N'Yara'),(10,N'Fadi'),(11,N'Rita'),(12,N'Ziad'),(13,N'Dana'),(14,N'Tarek'),(15,N'Mira'),
 (16,N'Sami'),(17,N'Lara'),(18,N'Jad'),(19,N'Tala'),(20,N'Elie'),(21,N'Joelle'),(22,N'Hassan'),(23,N'Reem'),
 (24,N'Georges'),(25,N'Christelle'),(26,N'Bilal'),(27,N'Hiba'),(28,N'Marc'),(29,N'Celine'),(30,N'Walid'),(31,N'Aya'),
 (32,N'Nader'),(33,N'Zeina'),(34,N'Charbel'),(35,N'Perla'),(36,N'Khaled'),(37,N'Rana'),(38,N'Antoine'),(39,N'Lina');

INSERT INTO @Last (i, Name) VALUES
 (0,N'Haddad'),(1,N'Khoury'),(2,N'Saad'),(3,N'Mansour'),(4,N'Nassar'),(5,N'Hachem'),(6,N'Aoun'),(7,N'Karam'),
 (8,N'Fares'),(9,N'Daher'),(10,N'Salameh'),(11,N'Hamdan'),(12,N'Issa'),(13,N'Rizk'),(14,N'Matar'),(15,N'Chahine'),
 (16,N'Sleiman'),(17,N'Ghanem'),(18,N'Abboud'),(19,N'Youssef'),(20,N'Kassab'),(21,N'Bitar'),(22,N'Nehme'),(23,N'Zein'),(24,N'Jaber');

INSERT INTO dbo.Customer (FullName, Email, PasswordSalt, PasswordHash)
SELECT f.Name + N' ' + l.Name,
       LOWER(f.Name) + N'.' + LOWER(l.Name) + CAST(x.n AS NVARCHAR(10)) + N'@example.com',
       CAST(NEWID() AS VARBINARY(16)),
       HASHBYTES('SHA2_256', CAST(NEWID() AS VARBINARY(16)))
FROM #Numbers x
JOIN @First f ON f.i = (x.n - 1) % 40
JOIN @Last  l ON l.i = ((x.n - 1) / 40) % 25
WHERE x.n <= @CustomerCount
ORDER BY x.n;                                  -- CustomerID 1..20000 follows n

DECLARE @S1 VARBINARY(16) = CRYPT_GEN_RANDOM(16),
        @S2 VARBINARY(16) = CRYPT_GEN_RANDOM(16),
        @S3 VARBINARY(16) = CRYPT_GEN_RANDOM(16);

INSERT INTO dbo.Customer (FullName, Email, Role, PasswordSalt, PasswordHash)
VALUES (N'Demo Customer', N'demo@tickethub.com',  'Customer', @S1, HASHBYTES('SHA2_256', @S1 + CAST(N'Demo123!'  AS VARBINARY(MAX)))),
       (N'Second Demo',   N'demo2@tickethub.com', 'Customer', @S2, HASHBYTES('SHA2_256', @S2 + CAST(N'Demo123!'  AS VARBINARY(MAX)))),
       (N'Staff Member',  N'staff@tickethub.com', 'Staff',    @S3, HASHBYTES('SHA2_256', @S3 + CAST(N'Staff123!' AS VARBINARY(MAX))));

IF OBJECT_ID('tempdb..#Sold') IS NOT NULL DROP TABLE #Sold;

WITH Sold AS
(
    SELECT e.EventID, s.SeatID,
           CASE s.Category WHEN 'VIP' THEN e.VipPrice ELSE e.StandardPrice END AS Price,
           ROW_NUMBER() OVER (PARTITION BY e.EventID ORDER BY s.SeatRow, s.SeatNumber) AS rn
    FROM dbo.Event e
    JOIN dbo.Seat  s ON s.VenueID = e.VenueID
    WHERE e.Status = 'Scheduled'
      AND (CHECKSUM(e.EventID, s.SeatID) & 0x7FFFFFFF) % 100 < CASE WHEN e.EventDate < @Now THEN 90 ELSE 50 END
)
SELECT EventID, SeatID, Price, CAST((rn - 1) / 4 AS INT) AS GroupNo
INTO #Sold
FROM Sold;

INSERT INTO dbo.Booking (CustomerID, EventID, BookingDate, TotalAmount, Status)
SELECT ((s.EventID * 7919 + s.GroupNo) % @CustomerCount) + 1,
       s.EventID,
       CASE WHEN DATEADD(DAY, -(1 + s.GroupNo % 60), e.EventDate) > @Now
            THEN DATEADD(MINUTE, -(s.GroupNo + 1) * 7, @Now)        -- upcoming event: booked recently
            ELSE DATEADD(DAY, -(1 + s.GroupNo % 60), e.EventDate)   -- booked 1-60 days before the event
       END,
       SUM(s.Price),
       'Active'
FROM #Sold s
JOIN dbo.Event e ON e.EventID = s.EventID
GROUP BY s.EventID, s.GroupNo, e.EventDate;

INSERT INTO dbo.Ticket (BookingID, EventID, SeatID, Price, Status)
SELECT b.BookingID, s.EventID, s.SeatID, s.Price, 'Active'
FROM #Sold s
JOIN dbo.Booking b
  ON b.EventID    = s.EventID
 AND b.CustomerID = ((s.EventID * 7919 + s.GroupNo) % @CustomerCount) + 1;

UPDATE dbo.Booking SET Status = 'Cancelled' WHERE BookingID % 40 = 0;

UPDATE t SET t.Status = 'Cancelled'
FROM dbo.Ticket t
JOIN dbo.Booking b ON b.BookingID = t.BookingID
WHERE b.Status = 'Cancelled';

UPDATE STATISTICS dbo.Ticket;
UPDATE STATISTICS dbo.Booking;

SELECT 'Venue' AS TableName, COUNT(*) AS NumberOfRows FROM dbo.Venue
UNION ALL SELECT 'Seat',     COUNT(*) FROM dbo.Seat
UNION ALL SELECT 'Event',    COUNT(*) FROM dbo.Event
UNION ALL SELECT 'Customer', COUNT(*) FROM dbo.Customer
UNION ALL SELECT 'Booking',  COUNT(*) FROM dbo.Booking
UNION ALL SELECT 'Ticket',   COUNT(*) FROM dbo.Ticket;

DROP TABLE #Sold;
DROP TABLE #Numbers;
GO

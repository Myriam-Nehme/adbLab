USE master;
GO

IF DB_ID(N'TicketHub') IS NOT NULL
BEGIN
    ALTER DATABASE TicketHub SET SINGLE_USER WITH ROLLBACK IMMEDIATE;  -- kick out open connections
    DROP DATABASE TicketHub;
END
GO

CREATE DATABASE TicketHub;
GO

USE TicketHub;
GO

CREATE SCHEMA app AUTHORIZATION dbo;
GO

CREATE TABLE dbo.Venue
(
    VenueID   INT IDENTITY(1,1) NOT NULL,
    Name      NVARCHAR(100)     NOT NULL,
    City      NVARCHAR(50)      NOT NULL,

    CONSTRAINT PK_Venue      PRIMARY KEY CLUSTERED (VenueID),
    CONSTRAINT UQ_Venue_Name UNIQUE (Name)
);

CREATE TABLE dbo.Seat
(
    SeatID     INT IDENTITY(1,1) NOT NULL,
    VenueID    INT               NOT NULL,
    SeatRow    TINYINT           NOT NULL,
    SeatNumber TINYINT           NOT NULL,
    Category   VARCHAR(10)       NOT NULL,

    CONSTRAINT PK_Seat               PRIMARY KEY CLUSTERED (SeatID),
    CONSTRAINT FK_Seat_Venue         FOREIGN KEY (VenueID) REFERENCES dbo.Venue (VenueID),
    CONSTRAINT UQ_Seat_Venue_Row_Num UNIQUE (VenueID, SeatRow, SeatNumber),   -- no duplicate seat in a venue
    CONSTRAINT CK_Seat_Category      CHECK (Category IN ('Standard', 'VIP')),
    CONSTRAINT CK_Seat_Row           CHECK (SeatRow >= 1),
    CONSTRAINT CK_Seat_Number        CHECK (SeatNumber >= 1)
);

CREATE TABLE dbo.Event
(
    EventID       INT IDENTITY(1,1) NOT NULL,
    VenueID       INT               NOT NULL,
    Title         NVARCHAR(150)     NOT NULL,
    EventDate     DATETIME2(0)      NOT NULL,
    StandardPrice DECIMAL(10,2)     NOT NULL,
    VipPrice      DECIMAL(10,2)     NOT NULL,
    Status        VARCHAR(10)       NOT NULL CONSTRAINT DF_Event_Status    DEFAULT ('Scheduled'),
    CreatedAt     DATETIME2(0)      NOT NULL CONSTRAINT DF_Event_CreatedAt DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_Event          PRIMARY KEY CLUSTERED (EventID),
    CONSTRAINT FK_Event_Venue    FOREIGN KEY (VenueID) REFERENCES dbo.Venue (VenueID),
    CONSTRAINT CK_Event_Status   CHECK (Status IN ('Scheduled', 'Cancelled')),
    CONSTRAINT CK_Event_Standard CHECK (StandardPrice > 0),
    CONSTRAINT CK_Event_Vip      CHECK (VipPrice >= StandardPrice)       -- VIP never cheaper than Standard
);

CREATE TABLE dbo.Customer
(
    CustomerID   INT IDENTITY(1,1) NOT NULL,
    FullName     NVARCHAR(100)     NOT NULL,
    Email        NVARCHAR(255)     NOT NULL,
    Role         VARCHAR(10)       NOT NULL CONSTRAINT DF_Customer_Role      DEFAULT ('Customer'),
    PasswordSalt VARBINARY(16)     NOT NULL,                             -- random bytes, one per user
    PasswordHash VARBINARY(32)     NOT NULL,                             -- SHA-256(salt + password)
    CreatedAt    DATETIME2(0)      NOT NULL CONSTRAINT DF_Customer_CreatedAt DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_Customer       PRIMARY KEY CLUSTERED (CustomerID),
    CONSTRAINT UQ_Customer_Email UNIQUE (Email),
    CONSTRAINT CK_Customer_Email CHECK (Email LIKE '%_@_%._%'),          -- basic email shape
    CONSTRAINT CK_Customer_Role  CHECK (Role IN ('Customer', 'Staff'))
);

CREATE TABLE dbo.Booking
(
    BookingID   INT IDENTITY(1,1) NOT NULL,
    CustomerID  INT               NOT NULL,
    EventID     INT               NOT NULL,
    BookingDate DATETIME2(0)      NOT NULL CONSTRAINT DF_Booking_Date   DEFAULT (SYSDATETIME()),
    TotalAmount DECIMAL(10,2)     NOT NULL,
    Status      VARCHAR(10)       NOT NULL CONSTRAINT DF_Booking_Status DEFAULT ('Active'),

    CONSTRAINT PK_Booking          PRIMARY KEY CLUSTERED (BookingID),
    CONSTRAINT FK_Booking_Customer FOREIGN KEY (CustomerID) REFERENCES dbo.Customer (CustomerID),
    CONSTRAINT FK_Booking_Event    FOREIGN KEY (EventID)    REFERENCES dbo.Event (EventID),
    CONSTRAINT CK_Booking_Total    CHECK (TotalAmount >= 0),
    CONSTRAINT CK_Booking_Status   CHECK (Status IN ('Active', 'Cancelled'))
);

CREATE TABLE dbo.Ticket
(
    TicketID  INT IDENTITY(1,1) NOT NULL,
    BookingID INT               NOT NULL,
    EventID   INT               NOT NULL,
    SeatID    INT               NOT NULL,
    Price     DECIMAL(10,2)     NOT NULL,                                -- price copied at booking time
    Status    VARCHAR(10)       NOT NULL CONSTRAINT DF_Ticket_Status DEFAULT ('Active'),

    CONSTRAINT PK_Ticket         PRIMARY KEY CLUSTERED (TicketID),
    CONSTRAINT FK_Ticket_Booking FOREIGN KEY (BookingID) REFERENCES dbo.Booking (BookingID),
    CONSTRAINT FK_Ticket_Event   FOREIGN KEY (EventID)   REFERENCES dbo.Event (EventID),
    CONSTRAINT FK_Ticket_Seat    FOREIGN KEY (SeatID)    REFERENCES dbo.Seat (SeatID),
    CONSTRAINT CK_Ticket_Price   CHECK (Price > 0),
    CONSTRAINT CK_Ticket_Status  CHECK (Status IN ('Active', 'Cancelled'))
);

CREATE TABLE dbo.BookingAudit
(
    AuditID     INT IDENTITY(1,1) NOT NULL,
    BookingID   INT               NOT NULL,
    CustomerID  INT               NOT NULL,
    EventID     INT               NOT NULL,
    Action      VARCHAR(20)       NOT NULL,
    Amount      DECIMAL(10,2)     NOT NULL,
    ActionDate  DATETIME2(0)      NOT NULL CONSTRAINT DF_Audit_Date DEFAULT (SYSDATETIME()),
    ActionBy    SYSNAME           NOT NULL CONSTRAINT DF_Audit_By   DEFAULT (SUSER_SNAME()),

    CONSTRAINT PK_BookingAudit    PRIMARY KEY CLUSTERED (AuditID),
    CONSTRAINT CK_BookingAudit_Ac CHECK (Action IN ('Booked', 'Cancelled'))
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_Ticket_Event_Seat_Active
    ON dbo.Ticket (EventID, SeatID)
    INCLUDE (Price)
    WHERE Status = 'Active';

CREATE NONCLUSTERED INDEX IX_Booking_Customer
    ON dbo.Booking (CustomerID, EventID)
    INCLUDE (BookingDate, TotalAmount, Status);

CREATE NONCLUSTERED INDEX IX_Ticket_Booking
    ON dbo.Ticket (BookingID)
    INCLUDE (SeatID, Price, Status);

CREATE NONCLUSTERED INDEX IX_Event_Date
    ON dbo.Event (EventDate)
    INCLUDE (VenueID, Title, Status, StandardPrice, VipPrice);
GO

CREATE TYPE app.SeatIdList AS TABLE
(
    SeatID INT NOT NULL PRIMARY KEY
);
GO

PRINT 'Schema created.';

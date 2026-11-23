using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Diagnostics;
using TicketHub.Api.Data;

var builder = WebApplication.CreateBuilder(args);

string connectionString = builder.Configuration.GetConnectionString("TicketHub")
    ?? throw new InvalidOperationException(
        "Connection string 'TicketHub' is missing. Set it with dotnet user-secrets " +
        "or the ConnectionStrings__TicketHub environment variable (see README).");

builder.Services.AddSingleton(new Db(connectionString));
builder.Services.AddControllers();

builder.Services
    .AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.Cookie.Name = "TicketHub.Auth";
        options.Cookie.HttpOnly = true;                       // JavaScript cannot read it
        options.Cookie.SameSite = SameSiteMode.Strict;        // not sent by other sites (CSRF)
        options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
        options.ExpireTimeSpan = TimeSpan.FromHours(8);
        options.SlidingExpiration = true;

        options.Events.OnRedirectToLogin = ctx => { ctx.Response.StatusCode = 401; return Task.CompletedTask; };
        options.Events.OnRedirectToAccessDenied = ctx => { ctx.Response.StatusCode = 403; return Task.CompletedTask; };
    });
builder.Services.AddAuthorization();

var app = builder.Build();

app.UseExceptionHandler(errorApp => errorApp.Run(async context =>
{
    var error = context.Features.Get<IExceptionHandlerFeature>()?.Error;
    var (status, message) = ErrorMapper.Map(error);

    if (status >= 500)
    {
        var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
        logger.LogError(error, "Unhandled error");
    }

    context.Response.StatusCode = status;
    await context.Response.WriteAsJsonAsync(new { error = message });
}));

app.UseDefaultFiles();
app.UseStaticFiles();

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();
app.MapFallbackToFile("index.html");

app.Run();

using System;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Azure.Messaging.ServiceBus;

namespace HomeAutomation.Functions
{
    public static class ReceiveRequest
    {
        [FunctionName("ReceiveRequest")]
        public static async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
            ILogger log)
        {
            string connectionString = Environment.GetEnvironmentVariable("sbcon") ?? "";
            string queueName = "triggerevents";

            string time = req.Query["t"];
            string doorName = req.Query["door"]; // Accept door name parameter

            int delaySeconds;

            if(int.TryParse(time, out delaySeconds) && !String.IsNullOrEmpty(doorName))
            {
                try
                {
                    // Use door mapping configuration to get enhanced event details
                    var (doorKey, doorConfig) = DoorMappingHelper.FindDoorByName(doorName, log);
                    
                    // Use configured delay (default 5 minutes) or provided time parameter
                    int configuredDelayMinutes = DoorMappingHelper.GetDelayMinutes(doorName, "opened", log);
                    int actualDelaySeconds = delaySeconds > 0 ? delaySeconds : configuredDelayMinutes * 60;
                    
                    // Get target device and announcement message from configuration
                    string targetDevice = DoorMappingHelper.GetTargetDevice(doorName, "opened", log);
                    string announceMessage = DoorMappingHelper.GetAnnouncementMessage(doorName, "opened", actualDelaySeconds / 60, log);
                    
                    ServiceBusClient client = new ServiceBusClient(connectionString);
                    ServiceBusSender sender = client.CreateSender(queueName); // Send to triggerevents queue
                    
                    // Message with door name for triggerevents queue
                    string messageText = $"{{\"DoorName\":\"{doorName}\",\"DoorKey\":\"{doorKey}\",\"DelaySeconds\":\"{actualDelaySeconds}\",\"TargetDevice\":\"{targetDevice}\",\"AnnounceMessage\":\"{announceMessage}\",\"EventType\":\"opened\"}}";
                    ServiceBusMessage message = new ServiceBusMessage(messageText);
                    message.MessageId = $"{doorName}_{DateTimeOffset.UtcNow.Ticks}"; // Unique message ID for duplicate detection

                    long seq = await sender.ScheduleMessageAsync(message, DateTimeOffset.Now.AddSeconds(actualDelaySeconds));
                    log.LogInformation($"Scheduled message for door: {doorName} (key: {doorKey}) with delay: {actualDelaySeconds}s, target: {targetDevice}");
                    
                    return new OkObjectResult($"Request received for {doorName}. Scheduled announcement in {actualDelaySeconds / 60} minutes to {targetDevice}.");
                }
                catch (Exception ex)
                {
                    log.LogError($"Error processing door event {doorName}: {ex.Message}");
                    
                    return new ObjectResult($"Error processing request for {doorName}: {ex.Message}")
                    {
                        StatusCode = 500
                    };
                }
            }
            else
            {
                return new BadRequestObjectResult("Invalid Request");
            }
        }
    }
}

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
    public static class CancelRequest
    {
        [FunctionName("CancelRequest")]
        public static async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
            ILogger log)
        {
            string connectionString = Environment.GetEnvironmentVariable("sbcon") ?? "";
            string doorName = req.Query["door"]; // Accept door name parameter like ReceiveRequest

            if (!String.IsNullOrEmpty(doorName))
            {
                try
                {
                    // Use door mapping configuration to get enhanced event details
                    var (doorKey, doorConfig) = DoorMappingHelper.FindDoorByName(doorName, log);
                    
                    // Use door mapping configuration to get the correct cancel queue
                    string cancelQueueName = DoorMappingHelper.GetCancelQueueName(doorName, "closed", log);
                    
                    ServiceBusClient client = new ServiceBusClient(connectionString);
                    ServiceBusSender sender = client.CreateSender(cancelQueueName);

                    // Enhanced cancel message with door mapping information
                    string messageContent = $"{{\"DoorName\":\"{doorName}\",\"DoorKey\":\"{doorKey}\",\"Action\":\"cancel\",\"EventType\":\"closed\",\"Timestamp\":\"{DateTimeOffset.UtcNow:yyyy-MM-ddTHH:mm:ssZ}\"}}";
                    ServiceBusMessage message = new ServiceBusMessage(messageContent);
                    message.MessageId = $"cancel_{doorName}_{DateTimeOffset.UtcNow.Ticks}";
                    message.TimeToLive = TimeSpan.FromMinutes(1); // Set TTL to 1 minute
                    
                    await sender.SendMessageAsync(message);
                    log.LogInformation($"Cancel request sent for door: {doorName} (key: {doorKey}) to queue: {cancelQueueName}");
                    
                    return new OkObjectResult($"Cancel request received for {doorName}. Sent to queue: {cancelQueueName}");
                }
                catch (Exception ex)
                {
                    log.LogError($"Error processing cancel request for {doorName}: {ex.Message}");
                    
                    return new ObjectResult($"Error processing cancel request for {doorName}: {ex.Message}")
                    {
                        StatusCode = 500
                    };
                }
            }
            else
            {
                return new BadRequestObjectResult("Invalid Request - door name and key are required");
            }
        }
    }
}

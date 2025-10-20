#nullable enable
using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace HomeAutomation.Functions
{
    public class AutomationEvent
    {
        public string? EventName { get; set; }
        public string? AnnounceFlowId { get; set; }
        public string? TimeDealay { get; set; }
    }

    public class DoorEvent
    {
        public string? DoorName { get; set; }
        public string? DoorKey { get; set; }
        public string? DelaySeconds { get; set; }
        public string? TargetDevice { get; set; }
        public string? AnnounceMessage { get; set; }
        public string? EventType { get; set; }
    }

    public class SendRequest
    {
        /// <summary>
        /// Generate appropriate announcement message based on event name and flow ID
        /// </summary>
        private static string GetAnnouncementMessage(string eventName, string announceFlowId)
        {
            // Check if this is a door event
            if (eventName.ToLower().Contains("door"))
            {
                if (eventName.ToLower().Contains("open"))
                {
                    return $"Door has been opened";
                }
                else if (eventName.ToLower().Contains("close"))
                {
                    return $"Door has been closed";
                }
            }
            
            // For other events, use a generic message
            return $"Automation event {eventName} has been triggered";
        }
        
        /// <summary>
        /// Determine target device based on event name
        /// </summary>
        private static string GetTargetDevice(string eventName)
        {
            string eventLower = eventName.ToLower();
            
            if (eventLower.Contains("bedroom"))
            {
                return "bedroom";
            }
            else if (eventLower.Contains("upstairs"))
            {
                return "upstairs";  
            }
            else if (eventLower.Contains("downstairs") || eventLower.Contains("main") || eventLower.Contains("front"))
            {
                return "downstairs";
            }
            
            // Default to all devices
            return "all";
        }

        /// <summary>
        /// Call the alexa-fn announce API
        /// </summary>
        private static async Task<bool> CallAlexaFnAnnounceApi(string message, string device, ILogger logger)
        {
            try
            {
                string alexaFnBaseUrl = Environment.GetEnvironmentVariable("ALEXA_FN_BASE_URL") ?? "";
                string alexaFnApiKey = Environment.GetEnvironmentVariable("ALEXA_FN_API_KEY") ?? "";
                
                if (string.IsNullOrEmpty(alexaFnBaseUrl))
                {
                    logger.LogWarning("ALEXA_FN_BASE_URL not configured");
                    return false;
                }
                
                if (string.IsNullOrEmpty(alexaFnApiKey))
                {
                    logger.LogWarning("ALEXA_FN_API_KEY not configured");
                    return false;
                }
                
                using HttpClient httpClient = new HttpClient();
                
                // Add the Azure Function function key as a header
                httpClient.DefaultRequestHeaders.Add("x-functions-key", alexaFnApiKey);
                
                var requestBody = new
                {
                    message = message,
                    device = device,
                    priority = "normal"
                };
                
                string jsonBody = JsonSerializer.Serialize(requestBody);
                var content = new StringContent(jsonBody, System.Text.Encoding.UTF8, "application/json");
                
                string url = $"{alexaFnBaseUrl}/api/announce";
                HttpResponseMessage response = await httpClient.PostAsync(url, content);
                
                if (response.IsSuccessStatusCode)
                {
                    string responseBody = await response.Content.ReadAsStringAsync();
                    logger.LogInformation($"Announce API called successfully: {responseBody}");
                    return true;
                }
                else
                {
                    logger.LogError($"Announce API call failed with status: {response.StatusCode}");
                    return false;
                }
            }
            catch (Exception ex)
            {
                logger.LogError($"Error calling alexa-fn announce API: {ex.Message}");
                return false;
            }
        }

        [FunctionName("SendRequest")]
        public static async Task RunAsync(
            [ServiceBusTrigger("triggerevents", Connection = "sbcon")] string myQueueItem,
            ILogger log)
        {
            string connectionString = Environment.GetEnvironmentVariable("sbcon") ?? "";

            ServiceBusClient client = new ServiceBusClient(connectionString);

            // Try to deserialize as new DoorEvent format first
            DoorEvent? doorEvent = null;
            AutomationEvent? automationEvent = null;
            
            try
            {
                doorEvent = JsonSerializer.Deserialize<DoorEvent>(myQueueItem);
            }
            catch
            {
                // Fallback to legacy AutomationEvent format
                automationEvent = JsonSerializer.Deserialize<AutomationEvent>(myQueueItem);
            }

            string eventName;
            string cancelQueueName;
            int delaySeconds;
            string message;
            string targetDevice;

            if (doorEvent?.DoorName != null)
            {
                // New door event format
                eventName = doorEvent.DoorName;
                cancelQueueName = DoorMappingHelper.GetCancelQueueName(doorEvent.DoorName, "opened", log);
                delaySeconds = int.Parse(doorEvent.DelaySeconds ?? "300");
                message = doorEvent.AnnounceMessage ?? $"The {doorEvent.DoorName} has been left open.";
                targetDevice = doorEvent.TargetDevice ?? "all";
            }
            else
            {
                // Legacy automation event format
                eventName = automationEvent?.EventName ?? string.Empty;
                cancelQueueName = eventName;
                delaySeconds = int.Parse(automationEvent?.TimeDealay ?? "0");
                
                message = GetAnnouncementMessage(eventName, automationEvent?.AnnounceFlowId ?? string.Empty);
                targetDevice = GetTargetDevice(eventName);
            }

            ServiceBusReceiver receiver = client.CreateReceiver(cancelQueueName);
            ServiceBusReceivedMessage receivedMessage = await receiver.ReceiveMessageAsync(TimeSpan.FromSeconds(2));

            if (receivedMessage != null)
            {
                await receiver.CompleteMessageAsync(receivedMessage);
                log.LogInformation($"Completed cancel message for event: {eventName}");
            }
            else
            {
                // Call alexa-fn announce API
                bool announceSuccess = await CallAlexaFnAnnounceApi(message, targetDevice, log);
                
                if (announceSuccess)
                {
                    log.LogInformation($"Successfully called alexa-fn announce API for: {eventName}");
                }
                else
                {
                    log.LogError($"Failed to call alexa-fn announce API for: {eventName}");
                }

                ServiceBusSender sender = client.CreateSender("triggerevents");
                ServiceBusMessage queueMessage = new ServiceBusMessage(myQueueItem);
                queueMessage.MessageId = eventName;
                long seq = await sender.ScheduleMessageAsync(queueMessage, DateTimeOffset.Now.AddSeconds(delaySeconds));
                log.LogInformation($"Scheduled message for event: {eventName} with delay: {delaySeconds}s");
            }
        }
    }
}

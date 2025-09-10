using System;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace HomeAutomation.Functions
{
    public class AutomationEvent
    {
        public string? EventName { get; set; }
        public string? AnnounceFlowId { get; set; }
        public string? TimeDealay { get; set; }
    }

    public class SendRequest
    {
        [Function("SendRequest")]
        public async Task RunAsync(
            [ServiceBusTrigger("triggerevents", Connection = "sbcon")] string myQueueItem,
            FunctionContext context)
        {
            var logger = context.GetLogger("SendRequest");
            string connectionString = Environment.GetEnvironmentVariable("sbcon") ?? "";
            string voiceMonkeyToken = Environment.GetEnvironmentVariable("VoiceMonkey__Token") ?? "";

            ServiceBusClient client = new ServiceBusClient(connectionString);

            AutomationEvent? automationEvent = JsonSerializer.Deserialize<AutomationEvent>(myQueueItem);
            string eventName = automationEvent?.EventName ?? string.Empty;
            string announceFlowId = automationEvent?.AnnounceFlowId ?? string.Empty;
            int delaySeconds = int.Parse(automationEvent?.TimeDealay ?? "0");

            ServiceBusReceiver receiver = client.CreateReceiver(eventName);
            ServiceBusReceivedMessage receivedMessage = await receiver.ReceiveMessageAsync(TimeSpan.FromSeconds(2));

            if (receivedMessage != null)
            {
                await receiver.CompleteMessageAsync(receivedMessage);
                logger.LogInformation($"Completed message for event: {eventName}");
            }
            else
            {
                var voiceMonkeyAnnounceFlow = $"https://api-v2.voicemonkey.io/flows?token={voiceMonkeyToken}&flow={announceFlowId}";
                HttpClient httpClient = new HttpClient();
                await httpClient.GetStringAsync(voiceMonkeyAnnounceFlow);
                logger.LogInformation($"Triggered VoiceMonkey flow for event: {eventName}");

                ServiceBusSender sender = client.CreateSender("triggerevents");
                ServiceBusMessage message = new ServiceBusMessage(myQueueItem);
                message.MessageId = eventName;
                long seq = await sender.ScheduleMessageAsync(message, DateTimeOffset.Now.AddSeconds(delaySeconds));
                logger.LogInformation($"Scheduled message for event: {eventName} with delay: {delaySeconds}s");
            }
        }
    }
}

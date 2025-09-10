using System;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Azure.Messaging.ServiceBus;

namespace HomeAutomation.Functions
{
    // ...existing code...
    public class ReceiveRequest
    {
        [Function("ReceiveRequest")]
        public async Task<HttpResponseData> Run(
            [HttpTrigger(AuthorizationLevel.Function, "get", "post")]
            HttpRequestData req,
            FunctionContext context)
        {
            var logger = context.GetLogger("ReceiveRequest");
            string connectionString = Environment.GetEnvironmentVariable("sbcon") ?? "";
            string queueName = "triggerevents";

            var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            string time = query["t"];
            string requestAuthKey = query["key"];
            string eventName = query["event"];
            string announceFlowId = query["announce"];
            string envAuthKey = Environment.GetEnvironmentVariable("AuthKey") ?? "";

            int delaySeconds;
            var response = req.CreateResponse();

            if(requestAuthKey == envAuthKey && int.TryParse(time, out delaySeconds) && !String.IsNullOrEmpty(eventName))
            {
                ServiceBusClient client = new ServiceBusClient(connectionString);
                ServiceBusSender sender = client.CreateSender(queueName);

                string messageText= $"{{\"EventName\":\"{eventName}\",\"AnnounceFlowId\":\"{announceFlowId}\", \"TimeDealay\":\"{time}\" }}";
                ServiceBusMessage message = new ServiceBusMessage(messageText);
                message.MessageId = eventName; // This enables duplicate detection

                long seq = await sender.ScheduleMessageAsync(message, DateTimeOffset.Now.AddSeconds(delaySeconds));
                logger.LogInformation($"Scheduled message for event: {eventName} with delay: {delaySeconds}s");
                response.StatusCode = System.Net.HttpStatusCode.OK;
                await response.WriteStringAsync("Request received");
            }
            else
            {
                response.StatusCode = System.Net.HttpStatusCode.BadRequest;
                await response.WriteStringAsync("Invalid Request");
            }
            return response;
        }
    }
}

using System;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Azure.Messaging.ServiceBus;

namespace HomeAutomation.Functions
{
    public class CancelRequest
    {
        [Function("CancelRequest")]
        public async Task<HttpResponseData> Run(
            [HttpTrigger(AuthorizationLevel.Function, "get", "post")] HttpRequestData req,
            FunctionContext context)
        {
            var logger = context.GetLogger("CancelRequest");
            string connectionString = Environment.GetEnvironmentVariable("sbcon") ?? "";
            var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            string requestAuthKey = query["key"];
            string eventName = query["event"];
            string envAuthKey = Environment.GetEnvironmentVariable("AuthKey") ?? "";

            var response = req.CreateResponse();

            if (requestAuthKey == envAuthKey && !String.IsNullOrEmpty(eventName))
            {
                ServiceBusClient client = new ServiceBusClient(connectionString);
                ServiceBusSender sender = client.CreateSender(eventName);

                ServiceBusMessage message = new ServiceBusMessage(eventName);
                await sender.SendMessageAsync(message);
                logger.LogInformation($"Cancel request sent for event: {eventName}");
                response.StatusCode = System.Net.HttpStatusCode.OK;
                await response.WriteStringAsync("Cancel Request received");
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

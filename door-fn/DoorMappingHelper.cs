using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Linq;
using Microsoft.Extensions.Logging;

namespace HomeAutomation.Functions
{
    /// <summary>
    /// Configuration models for door mapping
    /// </summary>
    public class DoorMappingConfig
    {
        public Dictionary<string, DoorConfig> Doors { get; set; } = new();
    }

    public class DoorConfig
    {
        public string CancelQueue { get; set; } = "";
        public string AnnounceMessage { get; set; } = "";
        public string TargetDevice { get; set; } = "";
    }

    /// <summary>
    /// Helper class to load and work with door mapping configuration
    /// </summary>
    public static class DoorMappingHelper
    {
        private static DoorMappingConfig? _config;
        private static readonly object _lock = new object();

        /// <summary>
        /// Load the door mapping configuration from JSON file
        /// </summary>
        public static DoorMappingConfig LoadConfiguration(ILogger? logger = null)
        {
            if (_config != null)
                return _config;

            lock (_lock)
            {
                if (_config != null)
                    return _config;

                try
                {
                    // Try multiple possible locations for the configuration file
                    string[] possiblePaths = new[]
                    {
                        Path.Combine(AppContext.BaseDirectory, "door-mapping.json"),
                        Path.Combine(Environment.CurrentDirectory, "door-mapping.json"),
                        Path.Combine(Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? "", "door-mapping.json"),
                        "door-mapping.json" // Current directory fallback
                    };

                    string configPath = "";
                    string jsonContent = "";

                    foreach (string path in possiblePaths)
                    {
                        if (File.Exists(path))
                        {
                            configPath = path;
                            jsonContent = File.ReadAllText(path);
                            logger?.LogInformation($"Found door mapping configuration at: {path}");
                            break;
                        }
                        else
                        {
                            logger?.LogDebug($"Configuration file not found at: {path}");
                        }
                    }
                    
                    if (string.IsNullOrEmpty(jsonContent))
                    {
                        logger?.LogWarning($"Door mapping configuration file not found in any of the expected locations. Using default configuration.");
                        _config = GetDefaultConfiguration();
                        return _config;
                    }
                    var options = new JsonSerializerOptions
                    {
                        PropertyNameCaseInsensitive = true,
                        ReadCommentHandling = JsonCommentHandling.Skip
                    };

                    _config = JsonSerializer.Deserialize<DoorMappingConfig>(jsonContent, options);
                    
                    if (_config == null)
                    {
                        logger?.LogError("Failed to deserialize door mapping configuration. Using default configuration.");
                        _config = GetDefaultConfiguration();
                    }
                    else
                    {
                        logger?.LogInformation($"Successfully loaded door mapping configuration with {_config.Doors.Count} doors.");
                    }

                    return _config;
                }
                catch (Exception ex)
                {
                    logger?.LogError($"Error loading door mapping configuration: {ex.Message}. Using default configuration.");
                    _config = GetDefaultConfiguration();
                    return _config;
                }
            }
        }

        /// <summary>
        /// Find door configuration by door name
        /// </summary>
        public static (string doorKey, DoorConfig? doorConfig) FindDoorByName(string doorName, ILogger? logger = null)
        {
            var config = LoadConfiguration(logger);
            string normalizedName = doorName.ToLower().Trim().Replace(" ", "_");

            // Try exact match with door keys
            if (config.Doors.ContainsKey(normalizedName))
            {
                return (normalizedName, config.Doors[normalizedName]);
            }

            // Try matching door keys that contain the normalized name
            foreach (var kvp in config.Doors)
            {
                if (kvp.Key.Contains(normalizedName) || normalizedName.Contains(kvp.Key))
                {
                    return (kvp.Key, kvp.Value);
                }
            }

            logger?.LogWarning($"Door configuration not found for: {doorName}");
            return (string.Empty, null);
        }

        /// <summary>
        /// Get the cancel queue name for a door event
        /// </summary>
        public static string GetCancelQueueName(string doorName, string eventType = "opened", ILogger? logger = null)
        {
            var (doorKey, doorConfig) = FindDoorByName(doorName, logger);
            
            if (doorConfig == null)
            {
                // Fallback to the queue name format used by alexa-fn
                string fallbackQueue = doorName.ToLower().Replace(" ", "_");
                logger?.LogInformation($"Using fallback queue name: {fallbackQueue}");
                return fallbackQueue;
            }

            return doorConfig.CancelQueue;
        }

        /// <summary>
        /// Get announcement message with dynamic content
        /// </summary>
        public static string GetAnnouncementMessage(string doorName, string eventType, int durationMinutes = 0, ILogger? logger = null)
        {
            var (doorKey, doorConfig) = FindDoorByName(doorName, logger);
            
            if (doorConfig == null)
            {
                return $"The {doorName} has been {eventType}.";
            }

            // Replace dynamic placeholders
            string message = doorConfig.AnnounceMessage;
            message = message.Replace("{duration}", durationMinutes.ToString());
            message = message.Replace("{door}", doorName);
            message = message.Replace("{event}", eventType);
            
            return message;
        }

        /// <summary>
        /// Get target device for announcement
        /// </summary>
        public static string GetTargetDevice(string doorName, string eventType = "opened", ILogger? logger = null)
        {
            var (doorKey, doorConfig) = FindDoorByName(doorName, logger);
            
            if (doorConfig == null)
            {
                return "downstairs"; // Default fallback
            }

            return doorConfig.TargetDevice;
        }

        /// <summary>
        /// Get delay in minutes for the event
        /// </summary>
        public static int GetDelayMinutes(string doorName, string eventType = "opened", ILogger? logger = null)
        {
            return 5; // Default 5 minutes as per original system
        }

        /// <summary>
        /// Default configuration if file is not found
        /// </summary>
        private static DoorMappingConfig GetDefaultConfiguration()
        {
            return new DoorMappingConfig
            {
                Doors = new Dictionary<string, DoorConfig>
                {
                    ["front_door"] = new()
                    {
                        CancelQueue = "front_door_unlocked",
                        AnnounceMessage = "The front door has been left unlocked for {duration} minutes.",
                        TargetDevice = "downstairs"
                    },
                    ["garage_door"] = new()
                    {
                        CancelQueue = "garage_door_open",
                        AnnounceMessage = "The garage door has been left open for {duration} minutes.",
                        TargetDevice = "downstairs"
                    }
                }
            };
        }
    }
}

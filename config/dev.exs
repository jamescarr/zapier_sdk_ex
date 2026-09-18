import Config

# Local development wiring for this machine's Zapier account.
#
# Connection IDs are account-specific, so they live here rather than in the
# README: this file is not part of the published package. Regenerate the list
# at any time with `ZapierSDK.list_connections/1`.
config :zapier_sdk,
  client_id: System.get_env("ZAPIER_CREDENTIALS_CLIENT_ID"),
  client_secret: System.get_env("ZAPIER_CREDENTIALS_CLIENT_SECRET"),
  connections: [
    drive: {"google-drive", "02069fbe-9c91-81c1-8567-8ee2dbb7ad64"},
    drive_alt: {"google-drive", "02010c30-cb0c-88e8-ba6d-0da09accec2a"},
    docs: {"google-docs", "022d50a1-9872-8c19-a0e8-3730d30c8016"},
    sheets: {"google-sheets", "0244419b-d799-8a87-9b51-36c9204618a1"},
    calendar: {"google-calendar", "022b29fb-7ea8-8663-ab2f-3ecd7775c511"},
    slack: {"slack", "02217725-24ba-8453-b2c2-75f41bf95747"},
    notion: {"NotionCLIAPI", "027c0ade-ce4a-860b-9e7c-e9f7acaea8c2"},
    coda: {"CodaCLIAPI", "024a2350-aa67-83a5-8849-1fe8a4ded868"},
    # This connection's OAuth grant has lapsed; reconnect it in Zapier before
    # use, or calls will return %ZapierSDK.Error{type: :connection_expired}.
    jira: {"jira-software-cloud", "025841e4-b17e-86f2-b9a4-6ef54df485ad"}
  ]

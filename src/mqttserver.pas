unit mqttserver;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Buffers, Logging, MQTTConsts, MQTTPackets, MQTTPacketDefs, MQTTSubscriptions,
  MQTTMessages;

{ Some default values for configuration parameters }

const
  MQTT_DEFAULT_KEEPALIVE             = 30;   // Seconds
  MQTT_DEFAULT_MAX_SESSION_AGE       = 1080; // Minutes
  MQTT_DEFAULT_MAX_SUBSCRIPTION_AGE  = 1080; // Minutes
  MQTT_DEFAULT_MAX_RESEND_ATTEMPTS   = 3;
  MQTT_DEFAULT_RESEND_PACKET_TIMEOUT = 2;    // Seconds

type
  TMQTTServer                     = class;
  TMQTTServerConnection           = class;
  TMQTTServerConnectionList       = class;
  TMQTTSessionList                = class;
  TMQTTSession                    = class;
  TMQTTRetainedMessagesDatastore  = class;

  TMQTTConnectionNotifyEvent      = procedure (AConnection: TMQTTServerConnection) of object;
  TMQTTValidateSubscriptionEvent  = procedure (AConnection: TMQTTServerConnection; ASubscription: TMQTTSubscription; var QOS: TMQTTQOSType; var Allow: Boolean) of object;
  TMQTTValidateClientIDEvent      = procedure (AServer: TMQTTServer; AClientID: UTF8String; var Allow: Boolean) of object;
  TMQTTValidatePasswordEvent      = procedure (AServer: TMQTTServer; AUsername, APassword: UTF8String; var Allow: Boolean) of object;
  TMQTTConnectionErrorEvent       = procedure (AConnection: TMQTTServerConnection; ErrCode: Word; ErrMsg: String) of object;
  TMQTTConnectionSendDataEvent    = procedure (AConnection: TMQTTServerConnection) of object;
  TMQTTConnectionDestroyEvent     = procedure (AConnection: TMQTTServerConnection) of object;
  TMQTTRetainedMessageListEvent   = procedure (Sender: TMQTTRetainedMessagesDatastore; AMessageList: TMQTTMessageList) of object;
  TMQTTDeleteRetainedMessageEvent = procedure (Sender: TMQTTRetainedMessagesDatastore; AClient, ATopic: UTF8String) of object;
  TMQTTUpdateRetainedMessageEvent = procedure (Sender: TMQTTRetainedMessagesDatastore; AClient, ATopic: UTF8String; Data: String; QOS: TMQTTQOSType) of object;

  EMQTTConnectionError            = class(Exception);

  { TMQTTServerConnection }

  TMQTTServerConnection = class(TLogObject)
    private
      FServer              : TMQTTServer;
      FSession             : TMQTTSession;
      FSocket              : TObject;
      FUsername            : UTF8String;
      FState               : TMQTTConnectionState;
      FInsufficientData    : Byte;
      FKeepAlive           : Word;
      FKeepAliveRemaining  : Word;
      FWillMessage         : TMQTTWillMessage;
      FClientIDGenerated   : Boolean;
      FRecvBuffer          : TBuffer;
      FSendBuffer          : TBuffer;
      procedure CheckTerminateSession;
      procedure HandleDISCONNECTPacket;
      procedure HandleCONNECTPacket(APacket: TMQTTCONNECTPacket);
      procedure HandlePINGREQPacket;
      procedure HandlePUBACKPacket(APacket: TMQTTPUBACKPacket);
      procedure HandlePUBCOMPPacket(APacket: TMQTTPUBCOMPPacket);
      procedure HandlePUBLISHPacket1(APacket: TMQTTPUBLISHPacket);
      procedure HandlePUBLISHPacket2(APacket: TMQTTPUBLISHPacket);
      procedure HandlePUBRECPacket(APacket: TMQTTPUBRECPacket);
      procedure HandlePUBRELPacket(APacket: TMQTTPUBRELPacket);
      procedure HandleSUBSCRIBEPacket(APacket: TMQTTSUBSCRIBEPacket);
      procedure HandleUNSUBSCRIBEPacket(APacket: TMQTTUNSUBSCRIBEPacket);
      procedure HandlePUBLISHPacket(APacket: TMQTTPUBLISHPacket);
      function InitNetworkConnection(APacket: TMQTTCONNECTPacket): byte;
      function InitSessionState(APacket: TMQTTCONNECTPacket): Boolean;
      function ValidateSubscription(ASubscription: TMQTTSubscription; var QOS: TMQTTQOSType): Boolean; virtual;
      procedure ValidateSubscriptions(AList: TMQTTSubscriptionList; ReturnCodes: TBuffer);
      procedure CheckTimeout;
      procedure SendWillMessage;
      procedure Accepted;
      procedure Timeout;
      procedure Disconnect;
      procedure Bail(ErrCode: Word);
    public
      constructor Create(AServer: TMQTTServer);
      destructor Destroy; override;
      procedure Publish(Topic: UTF8String; Data: String; QOS: TMQTTQOSType = qtAT_MOST_ONCE; Retain: Boolean = False; Duplicate: Boolean = False);
      procedure Disconnected;
      procedure DataAvailable(Buffer: TBuffer);
      property SendBuffer  : TBuffer read FSendBuffer;
      property RecvBuffer  : TBuffer read FRecvBuffer;
      property Socket      : TObject read FSocket write FSocket;
      property State       : TMQTTConnectionState read FState;
      property WillMessage : TMQTTWillMessage read FWillMessage write FWillMessage;
      property Server      : TMQTTServer read FServer;
      property Session     : TMQTTSession read FSession;
      property Username    : UTF8String read FUsername;
      property ClientIDGenerated : Boolean read FClientIDGenerated write FClientIDGenerated;
  end;

  { TMQTTServerConnectionList }

  TMQTTServerConnectionList = class(TObject)
    private
      FList: TList;
      function GetCount: Integer;
      function GetItem(Index: Integer): TMQTTServerConnection;
      procedure CheckTimeouts;
    public
      constructor Create;
      destructor Destroy; override;
      //
      procedure Clear;
      procedure Add(AConnection: TMQTTServerConnection);
      procedure Remove(AConnection: TMQTTServerConnection);
      procedure Delete(Index: Integer);
      //function Find(ClientID: UTF8String): TMQTTServerConnection;
      property Count: Integer read GetCount;
      property Items[Index: Integer]: TMQTTServerConnection read GetItem; default;
  end;

  { TMQTTRetainedMessagesDatastore }

  TMQTTRetainedMessagesDatastore = class(TComponent)
    private
      FFilename: String;
      FEnabled: Boolean;
      FModified: Boolean;
      FOnLoadDatastore: TMQTTRetainedMessageListEvent;
      FOnSaveDatastore: TMQTTRetainedMessageListEvent;
      FOnDeleteTopic: TMQTTDeleteRetainedMessageEvent;
      FOnUpdateTopic: TMQTTUpdateRetainedMessageEvent;
    public
      procedure LoadDatastore(Messages: TMQTTMessageList); virtual;
      procedure SaveDatastore(Messages: TMQTTMessageList); virtual;
      procedure DeleteTopic(ClientID, Topic: UTF8String); virtual;
      procedure UpdateTopic(ClientID, Topic: UTF8String; Data: String; QOS: TMQTTQOSType); virtual;
      property Modified: Boolean read FModified write FModified;
    published
      property Filename: String read FFilename write FFilename;
      property Enabled: Boolean read FEnabled write FEnabled;
      property OnLoadDatastore: TMQTTRetainedMessageListEvent read FOnLoadDatastore write FOnLoadDatastore;
      property OnSaveDatastore: TMQTTRetainedMessageListEvent read FOnSaveDatastore write FOnSaveDatastore;
      property OnDeleteTopic: TMQTTDeleteRetainedMessageEvent read FOnDeleteTopic write FOnDeleteTopic;
      property OnUpdateTopic: TMQTTUpdateRetainedMessageEvent read FOnUpdateTopic write FOnUpdateTopic;
  end;

  { TMQTTServerThread }

  TMQTTServerThread = class(TThread)
    private
      FServer: TMQTTServer;
      procedure OnTimer;
    protected
      procedure Execute; override;
  end;

  { TMQTTServer }

  TMQTTServer = class(TComponent)
    private
      FConnections                : TMQTTServerConnectionList;
      FSessions                   : TMQTTSessionList;
      FRetainedMessages           : TMQTTMessageList;
      FRetainedMessagesDatastore  : TMQTTRetainedMessagesDatastore;
      FResendPacketTimeout        : Byte;
      FMaxResendAttempts          : Byte;
      FMaxSubscriptionAge         : Word;
      FMaxSessionAge              : Word;
      FDefaultKeepAlive           : Integer;
      FEnabled                    : Boolean;
      FShutdown                   : Boolean;
      FRequireAuthentication      : Boolean;
      FAllowNullClientIDs         : Boolean;
      FStoreOfflineQoS0Messages: Boolean;
      FStrictClientIDValidation   : Boolean;
      FMaximumQOS                 : TMQTTQOSType;
      //
      FThread                     : TMQTTServerThread;
      FTimerTicks                 : Byte;                    // Accumulator
      // Connection related events
      FOnAccepted                 : TMQTTConnectionNotifyEvent;
      FOnDisconnect               : TMQTTConnectionNotifyEvent;
      FOnDisconnected             : TMQTTConnectionNotifyEvent;
      FOnError                    : TMQTTConnectionErrorEvent;
      FOnConnectionsChanged       : TNotifyEvent;
      FOnConnectionDestroy        : TMQTTConnectionDestroyEvent;
      //
      FOnSendData                 : TMQTTConnectionSendDataEvent;
      FOnValidateSubscription     : TMQTTValidateSubscriptionEvent;
      FOnValidateClientID         : TMQTTValidateClientIDEvent;
      FOnValidatePassword         : TMQTTValidatePasswordEvent;
      FOnSubscriptionsChanged     : TNotifyEvent;
      FOnSessionsChanged          : TNotifyEvent;
      FOnRetainedMessagesChanged  : TNotifyEvent;
      // Timer routines
      procedure ProcessAckQueues;
      procedure ProcessSessionAges;
      procedure HandleTimer;
      //
      procedure SetRetainedMessagesDatastore(AValue: TMQTTRetainedMessagesDatastore);
    protected
      procedure Notification(AComponent: TComponent; Operation: TOperation); override;
      // Methods that trigger event handlers
      procedure Accepted(Connection: TMQTTServerConnection); virtual;
      procedure Disconnected(Connection: TMQTTServerConnection); virtual;
      procedure Disconnect(Connection: TMQTTServerConnection); virtual;
      procedure SendData(Connection: TMQTTServerConnection); virtual;
      procedure DestroyConnection(Connection: TMQTTServerConnection); virtual;
      procedure ConnectionsChanged; virtual;
      procedure SubscriptionsChanged; virtual;
      procedure SessionsChanged; virtual;
      procedure RetainedMessagesChanged; virtual;
      procedure Loaded; override;
      //
      procedure DispatchMessage(Sender: TMQTTSession; Topic: UTF8String; Data: String; QOS: TMQTTQOSType; Retain: Boolean);
      procedure SendPendingTransmissionMessages;
      procedure SendRetainedMessages(Session: TMQTTSession; Subscription: TMQTTSubscription);
      function ValidateClientID(AClientID: UTF8String): Boolean; virtual;
      function ValidatePassword(AUsername, APassword: UTF8String): Boolean; virtual;
      property ResendPacketTimeout: Byte read FResendPacketTimeout write FResendPacketTimeout default MQTT_DEFAULT_RESEND_PACKET_TIMEOUT;
      property MaxResendAttempts: Byte read FMaxResendAttempts write FMaxResendAttempts default MQTT_DEFAULT_MAX_RESEND_ATTEMPTS;
    public
      Log: TLogDispatcher;
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      function StartConnection: TMQTTServerConnection; virtual;
      property Connections: TMQTTServerConnectionList read FConnections;
      property Sessions: TMQTTSessionList read FSessions;
      property RetainedMessages: TMQTTMessageList read FRetainedMessages;
    published
      property MaxSubscriptionAge: Word read FMaxSubscriptionAge write FMaxSubscriptionAge default MQTT_DEFAULT_MAX_SUBSCRIPTION_AGE;
      property MaxSessionAge: Word read FMaxSessionAge write FMaxSessionAge default MQTT_DEFAULT_MAX_SESSION_AGE;
      property KeepAlive: Integer read FDefaultKeepAlive write FDefaultKeepAlive default MQTT_DEFAULT_KEEPALIVE;
      property Enabled: Boolean read FEnabled write FEnabled default true;
      property MaximumQOS: TMQTTQOSType read FMaximumQOS write FMaximumQOS default qtEXACTLY_ONCE;
      property RequireAuthentication: Boolean read FRequireAuthentication write FRequireAuthentication default false;
      property AllowNullClientIDs: Boolean read FAllowNullClientIDs write FAllowNullClientIds default false;
      property StrictClientIDValidation: Boolean read FStrictClientIDValidation write FStrictClientIDValidation default false;
      property StoreOfflineQoS0Messages: Boolean read FStoreOfflineQoS0Messages write FStoreOfflineQoS0Messages default false;
      property RetainedMessagesDatastore: TMQTTRetainedMessagesDatastore read FRetainedMessagesDatastore write SetRetainedMessagesDatastore;
      //
      property OnAccepted                 : TMQTTConnectionNotifyEvent read FOnAccepted write FOnAccepted;
      property OnDisconnect               : TMQTTConnectionNotifyEvent read FOnDisconnect write FOnDisconnect;
      property OnDisconnected             : TMQTTConnectionNotifyEvent read FOnDisconnected write FOnDisconnected;
      property OnSendData                 : TMQTTConnectionSendDataEvent read FOnSendData write FOnSendData;
      property OnError                    : TMQTTConnectionErrorEvent read FOnError write FOnError;
      property OnConnectionsChanged       : TNotifyEvent read FOnConnectionsChanged write FOnConnectionsChanged;
      property OnConnectionDestroy        : TMQTTConnectionDestroyEvent read FOnConnectionDestroy write FOnConnectionDestroy;
      property OnValidateSubscription     : TMQTTValidateSubscriptionEvent read FOnValidateSubscription write FOnValidateSubscription;
      property OnValidateClientID         : TMQTTValidateClientIDEvent read FOnValidateClientID write FOnValidateClientID;
      property OnValidatePassword         : TMQTTValidatePasswordEvent read FOnValidatePassword write FOnValidatePassword;
      property OnSubscriptionsChanged     : TNotifyEvent read FOnSubscriptionsChanged write FOnSubscriptionsChanged;
      property OnSessionsChanged          : TNotifyEvent read FOnSessionsChanged write FOnSessionsChanged;
      property OnRetainedMessagesChanged  : TNotifyEvent read FOnRetainedMessagesChanged write FOnRetainedMessagesChanged;
  end;

  { TMQTTSession }

  TMQTTSession = class(TLogObject)
    private
      FServer              : TMQTTServer;
      FConnection          : TMQTTServerConnection;
      FSubscriptions       : TMQTTSubscriptionList;
      FPacketIDManager     : TMQTTPacketIDManager;
      FPendingReconnect    : TMQTTMessageList; // Messages to be retransmitted to the client when it reconnects.
      FPendingTransmission : TMQTTMessageList; // QoS 1 and QoS 2 messages pending transmission to the Client.
      FWaitingForAck       : TMQTTPacketQueue; // QoS 1 and QoS 2 messages which have been sent to the Client, but have not been completely acknowledged.
      FPendingDispatch     : TMQTTPacketQueue; // QoS 2 messages which have been received from the Client, but have not been completely acknowledged.
      FClientID            : UTF8String;
      FMaximumQOS          : TMQTTQOSType;
      FAge                 : Integer;
      FCleanSession        : Boolean;
      procedure SendRetainedMessages(NewSubscriptions: TMQTTSubscriptionList);
      procedure SendPendingTransmissionMessages;
      procedure SendPendingReconnectMessages;
      procedure ResendUnacknowledgedMessages;
      procedure DispatchMessage(Message: TMQTTMessage);
      procedure ProcessAckQueue;
      procedure ProcessSessionAges;
    public
      constructor Create(AServer: TMQTTServer; AClientID: UTF8String);
      destructor Destroy; override;
      procedure Clean;
      function GetQueueStatusStr: String;
      property Subscriptions: TMQTTSubscriptionList read FSubscriptions;
      property Server: TMQTTServer read FServer;
      property Connection: TMQTTServerConnection read FConnection write FConnection;
      property ClientID: UTF8String read FClientID;
      property MaximumQOS: TMQTTQOSType read FMaximumQOS write FMaximumQOS;
      property Age: Integer read FAge write FAge;
      property CleanSession: Boolean read FCleanSession write FCleanSession default True;
  end;

  { TMQTTSessionList }

  TMQTTSessionList = class(TObject)
    private
      FServer: TMQTTServer;
      FList: TList;
      function GenerateRandomClientID: UTF8String;
      function GetCount: Integer;
      function GetItem(Index: Integer): TMQTTSession;
      function GetRandomClientIDChar: Char;
    public
      constructor Create(AServer: TMQTTServer);
      destructor Destroy; override;
      //
      procedure Clear;
      function IsStrictlyValid(ClientID: UTF8String): Boolean;
      function GetUniqueClientID: UTF8String;
      function New(ClientID: UTF8String): TMQTTSession;
      procedure Add(AItem: TMQTTSession);
      function Find(ClientID: UTF8String): TMQTTSession;
      procedure Delete(Index: Integer);
      procedure Remove(AItem: TMQTTSession);
      // Properties
      property Server: TMQTTServer read FServer;
      property Count: Integer read GetCount;
      property Items[Index: Integer]: TMQTTSession read GetItem; default;
  end;

var
  MQTTStrictClientIDValidationChars: set of char = ['0'..'9','a'..'z','A'..'Z'];

implementation

uses
  MQTTTokenizer;

{ TMQTTRetainedMessagesDatastore }

procedure TMQTTRetainedMessagesDatastore.LoadDatastore(Messages: TMQTTMessageList);
var
  S: TFileStream;
begin
  if Enabled then
    begin
      if (Filename > '') and FileExists(Filename) then
        begin
          S := TFileStream.Create(Filename,fmOpenRead+fmShareDenyWrite);
          try
            Messages.LoadFromStream(S);
          finally
            S.Free;
          end;
        end;
      if Assigned(FOnLoadDatastore) then
        FOnLoadDatastore(Self,Messages);
      Modified := False;
    end;
end;

procedure TMQTTRetainedMessagesDatastore.SaveDatastore(Messages: TMQTTMessageList);
var
  S: TFileStream;
begin
  if Enabled then
    begin
      if (Filename > '') then
        begin
          if FileExists(Filename) then
            S := TFileStream.Create(Filename,fmOpenWrite+fmShareDenyRead)
          else
            S := TFileStream.Create(Filename,fmCreate);
          try
            Messages.SaveToStream(S);
          finally
            S.Free;
          end;
        end;
      if Assigned(FOnSaveDatastore) then
        FOnSaveDatastore(Self,Messages);
      Modified := False;
    end;
end;

procedure TMQTTRetainedMessagesDatastore.DeleteTopic(ClientID, Topic: UTF8String);
begin
  if Enabled and Assigned(FOnDeleteTopic) then
    begin
      Modified := True;
      OnDeleteTopic(Self,ClientID,Topic);
    end;
end;

procedure TMQTTRetainedMessagesDatastore.UpdateTopic(ClientID, Topic: UTF8String; Data: String; QOS: TMQTTQOSType);
begin
  if Enabled and Assigned(OnUpdateTopic) then
    begin
      Modified := True;
      OnUpdateTopic(Self,ClientID,Topic,Data,QOS);
    end;
end;

{ TMQTTServerThread }

procedure TMQTTServerThread.OnTimer;
begin
  FServer.HandleTimer;
end;

procedure TMQTTServerThread.Execute;
begin
  while not Terminated do
    begin
      Sleep(1000);
      if Assigned(FServer) then
        Synchronize(@OnTimer);
    end;
end;

{ TMQTTServer }

constructor TMQTTServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Log                     := TLogDispatcher.Create(Name);
  Log.Filter              := ALL_LOG_MESSAGE_TYPES;
  FMaximumQOS             := qtEXACTLY_ONCE;
  FEnabled                := True;
  FResendPacketTimeout    := 2;
  FMaxResendAttempts      := 3;
  FMaxSubscriptionAge     := 1080;
  FMaxSessionAge          := 1080;
  FDefaultKeepAlive       := 30;
  FRetainedMessages       := TMQTTMessageList.Create;
  FConnections            := TMQTTServerConnectionList.Create;
  FSessions               := TMQTTSessionList.Create(Self);
  //
  FThread                 := TMQTTServerThread.Create(False);
  FThread.FreeOnTerminate := True;
  FThread.FServer         := Self;
end;

destructor TMQTTServer.Destroy;
begin
  FShutdown := True;
  FThread.FServer := nil;
  FThread.Terminate;
  FSessions.Free;
  FConnections.Free;
  if Assigned(RetainedMessagesDatastore) and (RetainedMessagesDatastore.Enabled) then
    RetainedMessagesDatastore.SaveDatastore(RetainedMessages);
  FRetainedMessages.Free;
  Log.Free;
  inherited Destroy;
end;

procedure TMQTTServer.Notification(AComponent: TComponent; Operation: TOperation);
begin
  if (Operation = opRemove) and (AComponent = FRetainedMessagesDatastore) then
    FRetainedMessagesDatastore := nil;
  inherited Notification(AComponent, Operation);
end;

procedure TMQTTServer.ProcessSessionAges;
var
  X: Integer;
  Session: TMQTTSession;
begin
  for X := 0 to Sessions.Count - 1 do
    begin
      Session := Sessions[X];
      if Assigned(Session) then
        Session.ProcessSessionAges;
    end;
end;

procedure TMQTTServer.ProcessAckQueues;
var
  X: Integer;
  Session: TMQTTSession;
begin
  for X := 0 to Sessions.Count - 1 do
    begin
      Session := Sessions[X];
      if Assigned(Session) then
        Session.ProcessAckQueue;
    end;
end;

procedure TMQTTServer.HandleTimer;
begin
  // Runs every second
  Connections.CheckTimeouts;
  ProcessAckQueues;
  inc(FTimerTicks);
  if FTimerTicks = 60 then
    begin
      FTimerTicks := 0;
      // Runs every minute
      ProcessSessionAges;
    end;
end;

procedure TMQTTServer.Accepted(Connection: TMQTTServerConnection);
begin
  if Assigned(FOnAccepted) then
    FOnAccepted(Connection);
end;

procedure TMQTTServer.Disconnected(Connection: TMQTTServerConnection);
begin
  if Assigned(FOnDisconnected) then
    FOnDisconnected(Connection);
end;

procedure TMQTTServer.Disconnect(Connection: TMQTTServerConnection);
begin
  if Assigned(FOnDisconnect) then
    FOnDisconnect(Connection);
  Connections.Remove(Connection);
end;

procedure TMQTTServer.SendData(Connection: TMQTTServerConnection);
begin
  if Assigned(Connection) and Assigned(Connection.Session) then
    Connection.Session.Age := 0;
  if Assigned(FOnSendData) then
    FOnSendData(Connection);
end;

procedure TMQTTServer.DestroyConnection(Connection: TMQTTServerConnection);
begin
  if Assigned(FOnConnectionDestroy) then
    FOnConnectionDestroy(Connection);
end;

procedure TMQTTServer.ConnectionsChanged;
begin
  if (not FShutdown) and Assigned(FOnConnectionsChanged) then
    FOnConnectionsChanged(Self);
end;

procedure TMQTTServer.SubscriptionsChanged;
begin
  // Called after a batch of subscriptions has been updated or removed.
  // i.e. override to update stringgrids and treeviews in a UI
  if Assigned(FOnSubscriptionsChanged) then
    FOnSubscriptionsChanged(Self);
end;

procedure TMQTTServer.SessionsChanged;
begin
  if Assigned(FOnSessionsChanged) then
    FOnSessionsChanged(Self);
end;

procedure TMQTTServer.RetainedMessagesChanged;
begin
  if Assigned(FOnRetainedMessagesChanged) then
    FOnRetainedMessagesChanged(Self);
end;

procedure TMQTTServer.Loaded;
begin
  inherited Loaded;
  Log.Name := Name;
  if Assigned(RetainedMessagesDatastore) and RetainedMessagesDatastore.Enabled then
    RetainedMessagesDatastore.LoadDatastore(FRetainedMessages);
end;

function TMQTTServer.ValidateClientID(AClientID: UTF8String): Boolean;
begin
  Result := True;
  if Assigned(FOnValidateClientID) then
    FOnValidateClientID(Self,AClientID,Result);
end;

function TMQTTServer.ValidatePassword(AUsername, APassword: UTF8String): Boolean;
begin
  Result := False;
  if Assigned(FOnValidatePassword) then
    FOnValidatePassword(Self,AUsername,APassword,Result);
end;

function TMQTTServer.StartConnection: TMQTTServerConnection;
begin
  if FEnabled then
    Result := TMQTTServerConnection.Create(Self)
  else
    Result := nil;
end;

procedure TMQTTServer.DispatchMessage(Sender: TMQTTSession; Topic: UTF8String; Data: String; QOS: TMQTTQOSType; Retain: Boolean);
var
  I: Integer;
  S: TMQTTSession;
  M: TMQTTMessage;
begin
  M := TMQTTMessage.Create;
  try
    if Assigned(Sender) then
      M.ClientID := Sender.ClientID;
    M.Topic := Topic;
    M.Data := Data;
    M.QOS := QOS;
    M.Retain := Retain;
    if M.Tokens.Valid then
      begin
        if M.Retain then
          begin
            { A PUBLISH Packet with a RETAIN flag set to 1 and a payload containing zero bytes will be processed as
            normal by the Server and sent to Clients with a subscription matching the topic name. Additionally any
            existing retained message with the same topic name MUST be removed and any future subscribers for the
            topic will not receive a retained message [MQTT-3.3.1-10]. “As normal” means that the RETAIN flag is
            not set in the message received by existing Clients. A zero byte retained message MUST NOT be stored
            as a retained message on the Server [MQTT-3.3.1-11].}
            if M.Data = '' then
              begin
                RetainedMessages.DeleteByTopic(M.Topic);
                if Assigned(RetainedMessagesDatastore) and (RetainedMessagesDatastore.Enabled) then
                  FRetainedMessagesDatastore.DeleteTopic(Sender.ClientID,M.Topic);
              end
            else
              begin
                RetainedMessages.Update(M);
                if Assigned(RetainedMessagesDatastore) and (RetainedMessagesDatastore.Enabled) then
                  RetainedMessagesDatastore.UpdateTopic(Sender.ClientID,M.Topic,M.Data,M.QOS);
                M := M.Clone; // Store the message in the RetainedMessages list and continue processing using a clone of the original message
              end;
            RetainedMessagesChanged;
          end;
        M.Retain := False;
        for I := 0 to Sessions.Count - 1 do
          begin
            S := Sessions[I];
            if (Sender = nil) or (S <> Sender) then
              S.DispatchMessage(M);
          end;
      end;
  finally
    M.Free;
  end;
end;

procedure TMQTTServer.SendPendingTransmissionMessages;
var
  I: Integer;
  C: TMQTTServerConnection;
  S: TMQTTSession;
begin
  for I := 0 to Connections.Count - 1 do
    begin
      C := Connections[I];
      if Assigned(C) and (C.State <> csDisconnected) then
        begin
          S := C.Session;
          if Assigned(S) then
            S.SendPendingTransmissionMessages;
        end;
    end;
end;

procedure TMQTTServer.SendRetainedMessages(Session: TMQTTSession; Subscription: TMQTTSubscription);
var
  I: Integer;
  Message: TMQTTMessage;
begin
  for I := 0 to RetainedMessages.Count - 1 do
    begin
      Message := RetainedMessages[I];
      Message.Retain := True;
      if CheckTopicMatchesFilter(Message.Tokens,Subscription.Tokens) then
        Session.FPendingTransmission.Add(Message.Clone);
    end;
end;

procedure TMQTTServer.SetRetainedMessagesDatastore(AValue: TMQTTRetainedMessagesDatastore);
begin
  if FRetainedMessagesDatastore=AValue then Exit;
  if Assigned(FRetainedMessagesDatastore) then
    FRetainedMessagesDatastore.RemoveFreeNotification(Self);
  FRetainedMessagesDatastore:=AValue;
  if Assigned(FRetainedMessagesDatastore) then
    FRetainedMessagesDatastore.FreeNotification(Self);
end;

{ TMQTTServerConnection }

constructor TMQTTServerConnection.Create(AServer: TMQTTServer);
begin
  Assert(Assigned(AServer));
  inherited Create;
  Log.Name := 'Connection';
  Log.Filter := ALL_LOG_MESSAGE_TYPES;
  FServer  := AServer;
  FServer.Connections.Add(Self);
  FSendBuffer          := TBuffer.Create;
  FRecvBuffer          := TBuffer.Create;
  FKeepAlive           := Server.KeepAlive;
  FKeepAliveRemaining  := Round(FKeepAlive * 1.5);
  FWillMessage         := TMQTTWillMessage.Create;
  FServer.ConnectionsChanged;
end;

destructor TMQTTServerConnection.Destroy;
begin
  FServer.DestroyConnection(Self);
  FSocket := nil;
  FSession := nil;
  FWillMessage.Free;
  FSendBuffer.Free;
  FRecvBuffer.Free;
  FServer.Connections.Remove(Self);
  FServer.ConnectionsChanged;
  inherited Destroy;
end;

procedure TMQTTServerConnection.Accepted;
begin
  Assert(State = csConnecting);
  Log.Send(mtDebug,'New connection accepted');
  FState := csConnected;
  Server.ConnectionsChanged;
  Server.Accepted(Self);

end;

procedure TMQTTServerConnection.Timeout;
begin
  if (State = csConnected) then
    begin
      FState := csDisconnecting;
      Log.Send(mtWarning,'Connection timed out');
      SendWillMessage;
      if FState = csDisconnected then
        begin
          Server.Disconnect(Self);
          CheckTerminateSession;
          //if Assigned(FSession) then
          //  FSession.FConnection := nil;
          Destroy;
        end;
    end;
end;

procedure TMQTTServerConnection.CheckTerminateSession;
begin
  if Assigned(Session) then
    if ClientIDGenerated or Session.CleanSession then
      begin
        Log.Send(mtDebug,'Discarding session state for %s',[Session.ClientID]);
        // FSession.Clean; // Is this really necessary? Apparently not.
        Server.Sessions.Remove(FSession);
        FSession.Destroy;
        Server.SessionsChanged;
      end
    else
      begin
        Log.Send(mtDebug,'Retaining session state for %s',[Session.ClientID]);
        FSession.FConnection := nil;
      end;
end;

procedure TMQTTServerConnection.Disconnect;
begin
  if (State = csConnected) then
    begin
      Log.Send(mtInfo,'Connection disconnecting');
      FState := csDisconnecting;
      CheckTerminateSession;
      Server.Disconnect(Self);
      Destroy;
    end
  else
  if (State = csConnecting) then
    begin
      Log.Send(mtError,'Connection failed');
      FState := csDisconnecting;
      //CheckTerminateSession;
      Destroy;
    end;
end;

procedure TMQTTServerConnection.Disconnected;
begin
  if State = csConnected then
    begin
      FState := csDisconnecting;
      SendWillMessage;
    end;
  if State = csDisconnected then
    begin
      Log.Send(mtInfo,'Connection was disconnected');
      Server.Disconnected(Self);
      CheckTerminateSession;
      Destroy;
    end;
end;

procedure TMQTTServerConnection.Bail(ErrCode: Word);
var
  Msg: String;
begin
  Assert(State <> csDisconnected);
  FState := csDisconnecting;
  Msg := GetMQTTErrorMessage(ErrCode);
  Log.Send(mtError,'Bail: '+Msg);
  if Assigned(Server.FOnError) then
    Server.FOnError(Self,ErrCode,Msg);
  Server.Disconnect(Self);
  if Assigned(FSession) then
    FSession.FConnection := nil;
  FState := csDisconnected;
  Destroy;
end;

procedure TMQTTServerConnection.Publish(Topic: UTF8String; Data: String; QOS: TMQTTQOSType; Retain: Boolean; Duplicate: Boolean);
var
  Packet: TMQTTPUBLISHPacket;
begin
  Assert(State in [csConnected,csDisconnecting]);
  Packet := TMQTTPUBLISHPacket.Create;
  try
    Packet.QOS := QOS;
    if ord(Packet.QOS) > ord(Server.MaximumQOS) then
      Packet.QOS := Server.MaximumQOS;
    if ord(Packet.QOS) > ord(Session.MaximumQOS) then
      Packet.QOS := Session.MaximumQOS;
    Packet.Duplicate := Duplicate;
    Packet.Retain := Retain;
    Packet.Topic := Topic;
    Packet.Data := Data;
    if QOS in [qtAT_LEAST_ONCE, qtEXACTLY_ONCE] then
      begin
        Packet.PacketID := Session.FPacketIDManager.GenerateID;
        Session.FWaitingForAck.Add(Packet);
      end;
    Packet.WriteToBuffer(SendBuffer);
    Log.Send(mtDebug,'Sending PUBLISH (%d)',[Packet.PacketID]);
    Server.SendData(Self);
  finally
    if QOS = qtAT_MOST_ONCE then
      Packet.Free;
  end;
end;

procedure TMQTTServerConnection.DataAvailable(Buffer: TBuffer);
var
  Packet: TMQTTPacket;
  DestroyPacket: Boolean;
  ErrCode: Word;
begin
  DestroyPacket := True;
  Packet := nil;
  FKeepAliveRemaining := Round(FKeepAlive * 1.5); // Receipt of any data, even invalid data, should reset KeepAlive
  ErrCode := ReadMQTTPacketFromBuffer(Buffer,Packet,State = csConnected);
  try
    if ErrCode = MQTT_ERROR_NONE then
      begin
        if Assigned(Session) then
          Session.Age := 0;
        FInsufficientData := 0;
        if State = csConnected then
          begin
            case Packet.PacketType of
              ptDISCONNECT  : HandleDISCONNECTPacket;
              ptPINGREQ     : HandlePINGREQPacket;
              ptSUBSCRIBE   : HandleSUBSCRIBEPacket(Packet as TMQTTSUBSCRIBEPacket);
              ptUNSUBSCRIBE : HandleUNSUBSCRIBEPacket(Packet as TMQTTUNSUBSCRIBEPacket);
              ptPUBLISH     : HandlePUBLISHPacket(Packet as TMQTTPUBLISHPacket);
              ptPUBACK      : HandlePUBACKPacket(Packet as TMQTTPUBACKPacket);
              ptPUBREC      : HandlePUBRECPacket(Packet as TMQTTPUBRECPacket);
              ptPUBREL      : HandlePUBRELPacket(Packet as TMQTTPUBRELPacket);
              ptPUBCOMP     : HandlePUBCOMPPacket(Packet as TMQTTPUBCOMPPacket);
            else
              Bail(MQTT_ERROR_UNHANDLED_PACKETTYPE);
            end;
            if (Packet.PacketType = ptPUBLISH) and ((Packet as TMQTTPUBLISHPacket).QOS = qtEXACTLY_ONCE) then
              DestroyPacket := False;
          end
        else
          if State = csDisconnecting then
            case Packet.PacketType of
              ptPUBACK      : HandlePUBACKPacket(Packet as TMQTTPUBACKPacket);
              ptPUBREC      : HandlePUBRECPacket(Packet as TMQTTPUBRECPacket);
              ptPUBCOMP     : HandlePUBCOMPPacket(Packet as TMQTTPUBCOMPPacket);
            end
          else
            if (State = csNew) and (Packet is TMQTTCONNECTPacket) then
              HandleConnectPacket(Packet as TMQTTConnectPacket)
            else
              Bail(MQTT_ERROR_NOT_CONNECTED);
      end
    else
      if ErrCode = MQTT_ERROR_INSUFFICIENT_DATA then
        if FInsufficientData >= 2 then
          Bail(ErrCode)
        else
          inc(FInsufficientData)
      else
        Bail(ErrCode);

      // More data?
    if (ErrCode = MQTT_ERROR_NONE) and (Buffer.Size > 0) then
      DataAvailable(Buffer);
  finally
    if Assigned(Packet) and (DestroyPacket) then
      FreeAndNil(Packet);
  end;
end;

function TMQTTServerConnection.InitNetworkConnection(APacket: TMQTTCONNECTPacket): byte;
var
  X: Integer;
  C: TMQTTServerConnection;
begin
  Assert(State = csConnecting);

  // See if a return code has already been set by the parser.
  Result := APacket.ReturnCode;
  if Result <> MQTT_CONNACK_SUCCESS then Exit;

  // Check to ensure the server is active
  if not Server.Enabled then
    begin
      Result := MQTT_CONNACK_SERVER_UNAVAILABLE;
      Exit;
    end;

  // If a zero length ClientID is provided, generate a unique random ClientID

  { A Server MAY allow a Client to supply a ClientId that has a length of zero
    bytes, however if it does so the Server MUST treat this as a special case
    and assign a unique ClientId to that Client. It MUST then process the CONNECT
    packet as if the Client had provided that unique ClientId [MQTT-3.1.3-6]}

  if APacket.ClientID = '' then
    if APacket.CleanSession and Server.AllowNullClientIDs then
      begin
        APacket.ClientID := Server.Sessions.GetUniqueClientID;
        FClientIDGenerated := True;
      end
    else
      begin
        Result := MQTT_CONNACK_CLIENTID_REJECTED;  { Can't reconnect to a session when no ClientID provided }
        Exit;
      end
  else
    FClientIDGenerated := False;

  // See if the ClientID conforms to the optional strict requirements for a ClientID
  if Server.StrictClientIDValidation and not Server.Sessions.IsStrictlyValid(APacket.ClientID) then
    begin
      Result := MQTT_CONNACK_CLIENTID_REJECTED;
      Exit;
    end;

  // Check the ClientID Whitelists and Blaclists
  if not Server.ValidateClientID(APacket.ClientID) then
    begin
      Result := MQTT_CONNACK_CLIENTID_REJECTED;
      Exit;
    end;

  // Disconnect any other connections with a matching ClientID
  for X := Server.Connections.Count - 1 downto 0 do
    begin
      C := Server.Connections[X];
      if (C <> Self) and Assigned(C.Session) and (C.Session.ClientID = APacket.ClientID) then
        C.Disconnect;
    end;

  // Authenticate the user and assign the user variable
  if APacket.UsernameFlag then
    begin
      FUsername := APacket.Username;
      if not Server.ValidatePassword(FUsername,APacket.Password) then
        begin
          Result := MQTT_CONNACK_NOT_AUTHORIZED;
          Exit;
        end;
    end
  else
    begin
      FUsername := '';
      if Server.RequireAuthentication then
        begin
          Result := MQTT_CONNACK_NOT_AUTHORIZED;
          Exit;
        end;
    end;
end;

function TMQTTServerConnection.InitSessionState(APacket: TMQTTCONNECTPacket): Boolean;
begin
  Assert(State=csConnecting);
  // Retrieve existing session, if any
  FSession := Server.Sessions.Find(APacket.ClientID);
  if Assigned(FSession) then
    begin
      // If an existing session is found and the client is requesting a
      // clean session then clean that session.
      Result := not APacket.CleanSession;
      if APacket.CleanSession then
        FSession.Clean
      else
        begin
          FSession.CleanSession := False;
          FSession.ResendUnacknowledgedMessages; // Resend any unacknowledged PUBLISH or PUBREL messages
          FSession.SendPendingReconnectMessages; // Send any messages received while offline
        end;
    end
  else
    begin
      // Otherwise create a new one
      Result := False;
      FSession := Server.Sessions.New(APacket.ClientID);
      FSession.CleanSession := APacket.CleanSession;
    end;

  // Initialize the session state
  FSession.FConnection := Self;
  FKeepAlive           := APacket.KeepAlive;
  FKeepAliveRemaining  := Round(FKeepAlive * 1.5);
  Log.Name             := 'Connection['+Session.ClientID+']';
  Session.Log.Name     := 'Session['+Session.ClientID+']';
  FWillMessage.Assign(APacket.WillMessage);
  if ord(Server.MaximumQOS) < ord(WillMessage.QOS) then
    WillMessage.QOS := Server.MaximumQOS;
  //
  Server.SessionsChanged;
end;

function TMQTTServerConnection.ValidateSubscription(ASubscription: TMQTTSubscription; var QOS: TMQTTQOSType): Boolean;
begin
  // Note: 3.8.4 says "The Server might grant a lower maximum QoS than the
  // subscriber requested".  To do this, change the value of QOS to a lower value.

  // Note: 3.9.3 there is the opportunity to send an error code in the SUBACK response.
  // To do that, return false.

  Result := ASubscription.Tokens.Valid;
  if Assigned(Server.FOnValidateSubscription) then
    Server.FOnValidateSubscription(Self,ASubscription,QOS,Result);
  if ord(QOS) > ord(Server.MaximumQOS) then
    QOS := Server.MaximumQOS;
end;

procedure TMQTTServerConnection.ValidateSubscriptions(AList: TMQTTSubscriptionList; ReturnCodes: TBuffer);
var
  I: Integer;
  S: TMQTTSubscription;
  Q: TMQTTQOSType;
  RC: Byte;
begin
  Assert(Assigned(AList) and Assigned(ReturnCodes));
  for I := 0 to AList.Count - 1 do
    begin
      S := AList[I];
      Q := S.QOS;
      if ValidateSubscription(S,Q) then
        begin
          RC := ord(Q);
          S.QOS := Q;
        end
      else
        begin
          RC := $80;
          Log.Send(mtWarning,'Subscription %s was not added because it generated an error',[S.Filter]);
          AList.Delete(I);
          // S.Free; // Handled by AList.Delete(I)
        end;
      ReturnCodes.Write(@RC,1);
    end;
end;

procedure TMQTTServerConnection.CheckTimeout;
begin
  if FKeepAliveRemaining = 1 then
    Timeout
  else
    if FKeepAliveRemaining > 0 then
      dec(FKeepAliveRemaining);
end;

procedure TMQTTServerConnection.SendWillMessage;
begin
  Assert(State = csDisconnecting);
  if WillMessage.Enabled then
    begin
      Log.Send(mtDebug,'Sending Will Message (%s)',[WillMessage.AsString]);
      Publish(WillMessage.Topic,WillMessage.Data,WillMessage.QOS,WillMessage.Retain,False);
      if WillMessage.QOS = qtAT_MOST_ONCE then
        FState := csDisconnected;
    end
  else
    FState := csDisconnected;
end;

procedure TMQTTServerConnection.HandleDISCONNECTPacket;
begin
  Log.Send(mtDebug,'Received DISCONNECT');
  Disconnect;
end;

procedure TMQTTServerConnection.HandleCONNECTPacket(APacket: TMQTTCONNECTPacket);
var
  SessionPresent : Boolean;
  ReturnCode     : Byte;
  Reply          : TMQTTCONNACKPacket;
begin
  Assert(State = csNew);
  FState := csConnecting;
  ReturnCode := InitNetworkConnection(APacket);

  if ReturnCode <> MQTT_CONNACK_SUCCESS then
    SessionPresent := False
  else
    SessionPresent := InitSessionState(APacket);

  Log.Send(mtDebug,'Received CONNECT (%s)',[APacket.AsString]);

  Reply := TMQTTCONNACKPACKET.Create;
  try
    Reply.ReturnCode := ReturnCode;
    Reply.SessionPresent := SessionPresent;
    Reply.WriteToBuffer(SendBuffer);
    Log.Send(mtDebug,'Sending CONNACK (%s)',[Reply.AsString]);
    Server.SendData(Self);
    if ReturnCode = MQTT_CONNACK_SUCCESS then
      Accepted
    else
      Disconnect;
  finally
    Reply.Free;
  end;
end;

procedure TMQTTServerConnection.HandlePINGREQPacket;
var
  Reply: TMQTTPINGRESPPacket;
begin
  //Log.Send(mtDebug,'Received PINGREQ');
  Reply := TMQTTPINGRESPPacket.Create;
  try
    // KeepAlive is reset in DataAvailable() in response to all packets
    Reply.WriteToBuffer(SendBuffer);
    //Log.Send(mtDebug,'Sending PINGRESP');
    Server.SendData(Self);
  finally
    Reply.Free;
  end;
end;

procedure TMQTTServerConnection.HandleSUBSCRIBEPacket(APacket: TMQTTSUBSCRIBEPacket);
var
  Reply: TMQTTSUBACKPacket;
begin
  Log.Send(mtDebug,'Received SUBSCRIBE (%s)',[APacket.AsString]);
  Reply := TMQTTSUBACKPacket.Create;
  try
    Reply.PacketID := APacket.PacketID;
    ValidateSubscriptions(APacket.Subscriptions,Reply.ReturnCodes);
    Session.Subscriptions.MergeList(APacket.Subscriptions);
    // Send the data
    Reply.WriteToBuffer(SendBuffer);
    Log.Send(mtDebug,'Sending SUBACK (%s)',[Reply.AsString]);
    Server.SendData(Self);
    Server.SubscriptionsChanged;
    Session.SendRetainedMessages(APacket.Subscriptions);
  finally
    Reply.Free;
  end;
end;

procedure TMQTTServerConnection.HandleUNSUBSCRIBEPacket(APacket: TMQTTUNSUBSCRIBEPacket);
var
  Reply: TMQTTUNSUBACKPacket;
begin
  Log.Send(mtDebug,'Received UNSUBSCRIBE (%s)',[APacket.AsString]);
  Reply := TMQTTUNSUBACKPacket.Create;
  try
    Reply.PacketID := APacket.PacketID;
    if APacket.Subscriptions.RemoveInvalidSubscriptions > 0 then
      Bail(MQTT_ERROR_INVALID_SUBSCRIPTION_ENTRIES);
    Session.Subscriptions.DeleteList(APacket.Subscriptions);
    // Send the data
    Reply.WriteToBuffer(SendBuffer);
    Log.Send(mtDebug,'Sending UNSUBACK (%s)',[Reply.AsString]);
    Server.SendData(Self);
    Server.SubscriptionsChanged;
  finally
    Reply.Free;
  end;
end;

procedure TMQTTServerConnection.HandlePUBACKPacket(APacket: TMQTTPUBACKPacket);
begin
  Log.Send(mtDebug,'Received PUBACK (%s)',[APacket.AsString]);
  Session.FPacketIDManager.ReleaseID(APacket.PacketID);
  Session.FWaitingForAck.Remove(ptPUBLISH,APacket.PacketID);
  // Disconnects the connection after the willmessage has been sent
  if State = csDisconnecting then
    Disconnected;
end;

procedure TMQTTServerConnection.HandlePUBRECPacket(APacket: TMQTTPUBRECPacket);
var
  Reply: TMQTTPUBRELPacket;
begin
  Log.Send(mtDebug,'Received PUBREC (%s)',[APacket.AsString]);
  Session.FWaitingForAck.Remove(ptPublish,APacket.PacketID);

  Reply := TMQTTPUBRELPacket.Create;
  Reply.PacketID := APacket.PacketID;
  Session.FWaitingForAck.Add(Reply);
  Reply.WriteToBuffer(SendBuffer);
  Log.Send(mtDebug,'Sending PUBREL (%s)',[Reply.AsString]);
  Server.SendData(Self);
end;

procedure TMQTTServerConnection.HandlePUBRELPacket(APacket: TMQTTPUBRELPacket);
var
  Pkt: TMQTTPUBLISHPacket;
  Reply: TMQTTPUBCOMPPacket;
begin
  Log.Send(mtDebug,'Received PUBREL (%s)',[APacket.AsString]);
  Session.FWaitingForAck.Remove(ptPUBREC,APacket.PacketID);
  Pkt := Session.FPendingDispatch.Find(ptPUBLISH,APacket.PacketID) as TMQTTPUBLISHPacket;
  if Assigned(Pkt) then
    begin
      Server.DispatchMessage(Session,Pkt.Topic,Pkt.Data,Pkt.QOS,Pkt.Retain);
      Session.FPendingDispatch.Remove(Pkt);
      Pkt.Free;
    end;
  Reply := TMQTTPUBCOMPPacket.Create;
  try
    Reply.PacketID := APacket.PacketID;
    Reply.WriteToBuffer(SendBuffer);
    Log.Send(mtDebug,'Sending PUBCOMP (%s)',[Reply.AsString]);
    Server.SendData(Self);
    Server.SendPendingTransmissionMessages;
  finally
    Reply.Free;
  end;
end;

procedure TMQTTServerConnection.HandlePUBCOMPPacket(APacket: TMQTTPUBCOMPPacket);
begin
  Log.Send(mtDebug,'Received PUBCOMP (%s)',[APacket.AsString]);
  Session.FPacketIDManager.ReleaseID(APacket.PacketID);
  Session.FWaitingForAck.Remove(ptPUBREL,APacket.PacketID);
  // Disconnects the connection after the willmessage has been sent
  if State = csDisconnecting then
    Disconnected;
end;

procedure TMQTTServerConnection.HandlePUBLISHPacket1(APacket: TMQTTPUBLISHPacket);
var
  Reply: TMQTTPUBACKPacket;
begin
  Reply := TMQTTPUBACKPacket.Create;
  try
    Reply.PacketID := APacket.PacketID;
    Reply.WriteToBuffer(SendBuffer);
    Log.Send(mtDebug,'Sending PUBACK (%s)',[Reply.AsString]);
    Server.SendData(Self);
    Server.DispatchMessage(Session,APacket.Topic,APacket.Data,APacket.QOS,APacket.Retain);
    Server.SendPendingTransmissionMessages;
  finally
    Reply.Free;
  end;
end;

procedure TMQTTServerConnection.HandlePUBLISHPacket2(APacket: TMQTTPUBLISHPacket);
var
  Pkt    : TMQTTPUBLISHPacket;
  Reply  : TMQTTPUBRECPacket;
begin
  // If the duplicate flag is set, ensure we don't add the packet to the pending dispatch list twice
  if APacket.Duplicate then
    Pkt := Session.FPendingDispatch.Find(ptPublish,APacket.PacketID) as TMQTTPUBLISHPacket
  else
    Pkt := nil;
  if not Assigned(Pkt) then
    begin
      Pkt := APacket;
      Session.FPendingDispatch.Add(APacket);
    end;
  Reply := TMQTTPUBRECPacket.Create;
  Reply.PacketID := Pkt.PacketID;
  Session.FWaitingForAck.Add(Reply);
  Reply.WriteToBuffer(SendBuffer);
  Log.Send(mtDebug,'Sending PUBREC (%s)',[Reply.AsString]);
  Server.SendData(Self);
end;

procedure TMQTTServerConnection.HandlePUBLISHPacket(APacket: TMQTTPUBLISHPacket);
begin
  Log.Send(mtDebug,'Received PUBLISH (%s)',[APacket.AsString]);
  case APacket.QOS of
    qtAT_MOST_ONCE  : Server.DispatchMessage(Session,APacket.Topic,APacket.Data,APacket.QOS,APacket.Retain);
    qtAT_LEAST_ONCE : HandlePUBLISHPacket1(APacket);
    qtEXACTLY_ONCE  : HandlePUBLISHPacket2(APacket);
  end;
end;

{ TMQTTServerConnectionList }

constructor TMQTTServerConnectionList.Create;
begin
  inherited Create;
  FList := TList.Create;
end;

destructor TMQTTServerConnectionList.Destroy;
begin
  Clear;
  FList.Free;
  inherited Destroy;
end;

function TMQTTServerConnectionList.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TMQTTServerConnectionList.GetItem(Index: Integer): TMQTTServerConnection;
begin
  Result := TMQTTServerConnection(FList[Index]);
end;

procedure TMQTTServerConnectionList.CheckTimeouts;
var
  X: Integer;
  Connection: TMQTTServerConnection;
begin
  for X := Count - 1 downto 0 do
    begin
      Connection := Items[X];
      if Assigned(Connection) then
        Connection.CheckTimeout;
    end;
end;

procedure TMQTTServerConnectionList.Clear;
var
  I: Integer;
begin
  for I := Count - 1 downto 0 do
    Items[I].Free;
  FList.Clear;
end;

procedure TMQTTServerConnectionList.Add(AConnection: TMQTTServerConnection);
begin
  FList.Add(AConnection);
end;

procedure TMQTTServerConnectionList.Remove(AConnection: TMQTTServerConnection);
begin
  FList.Remove(AConnection);
end;

procedure TMQTTServerConnectionList.Delete(Index: Integer);
begin
  FList.Delete(Index);
end;

{ TMQTTSessionList }

constructor TMQTTSessionList.Create(AServer: TMQTTServer);
begin
  inherited Create;
  FServer := AServer;
  FList := TList.Create;
end;

destructor TMQTTSessionList.Destroy;
begin
  Clear;
  FList.Free;
  inherited Destroy;
end;

function TMQTTSessionList.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TMQTTSessionList.GetItem(Index: Integer): TMQTTSession;
begin
  Result := TMQTTSession(FList[Index]);
end;

procedure TMQTTSessionList.Clear;
var
  X: Integer;
begin
  for X := Count - 1 downto 0 do
    Items[X].Destroy;
  FList.Clear;
end;

function TMQTTSessionList.GetRandomClientIDChar: Char;
var
  B: Byte;
begin
  B := Random(62) + 1;
  if B < 10 then
    Result := chr($30 + B)
  else
    if B < 36 then
      Result := chr($41 + (B - 10))
    else
      Result := chr($61 + (B - 36));
end;

function TMQTTSessionList.GenerateRandomClientID: UTF8String;
var
  X: Integer;
begin
  SetLength(Result,23);
  for X := 1 to 23 do
    Result[X] := GetRandomClientIDChar;
end;

function TMQTTSessionList.GetUniqueClientID: UTF8String;
begin
  repeat
    Result := GenerateRandomClientID;
  until Find(Result) = nil;
end;

function TMQTTSessionList.IsStrictlyValid(ClientID: UTF8String): Boolean;
var
  X,L: Integer;
  C: Char;
begin
  Result := True;
  L := Length(ClientID);
  if L < 24 then
    for X := 1 to L do
      begin
        C := ClientID[X];
        if not (C in MQTTStrictClientIDValidationChars) then
          begin
            Result := False;
            Exit;
          end;
      end
  else
    Result := False;
end;

function TMQTTSessionList.New(ClientID: UTF8String): TMQTTSession;
begin
  Result := TMQTTSession.Create(FServer,ClientID);
  FList.Add(Result);
end;

procedure TMQTTSessionList.Add(AItem: TMQTTSession);
begin
  FList.Add(AItem);
end;

function TMQTTSessionList.Find(ClientID: UTF8String): TMQTTSession;
var
  X: Integer;
begin
  for X := 0 to Count - 1 do
    begin
      Result := Items[X];
      if Result.ClientID = ClientID then Exit;
    end;
  Result := nil;
end;

procedure TMQTTSessionList.Delete(Index: Integer);
begin
  FList.Delete(Index);
end;

procedure TMQTTSessionList.Remove(AItem: TMQTTSession);
begin
  FList.Remove(AItem);
end;

{ TMQTTSession }

constructor TMQTTSession.Create(AServer: TMQTTServer; AClientID: UTF8String);
begin
  inherited Create;
  FServer              := AServer;
  FSubscriptions       := TMQTTSubscriptionList.Create;
  FPendingReconnect    := TMQTTMessageList.Create;
  FPendingTransmission := TMQTTMessageList.Create;
  FPendingDispatch     := TMQTTPacketQueue.Create;
  FPacketIDManager     := TMQTTPacketIDManager.Create;
  FWaitingForAck       := TMQTTPacketQueue.Create;
  FClientID            := AClientID;
  FMaximumQOS          := qtEXACTLY_ONCE;
  FCleanSession        := True;
  Log.Name             := 'Session ('+FClientID+')';
  Log.Filter           := ALL_LOG_MESSAGE_TYPES;
end;

destructor TMQTTSession.Destroy;
begin
  FSubscriptions.Free;
  FPendingReconnect.Free;
  FPendingTransmission.Free;
  FPendingDispatch.Free;
  FPacketIDManager.Free;
  FWaitingForAck.Free;
  inherited Destroy;
end;

procedure TMQTTSession.Clean;
begin // Reset the session to a clean state.
  FSubscriptions.Clear;
  FPendingReconnect.Clear;
  FPendingTransmission.Clear;
  FWaitingForAck.Clear;
  FPendingDispatch.Clear;
  FPacketIDManager.Reset;
  FAge := 0;
  FCleanSession := True;
end;

function TMQTTSession.GetQueueStatusStr: String;
begin
  Result := Format('%d PR, %d PT, %d WA, %d PD',[FPendingReconnect.Count,FPendingTransmission.Count,FWaitingForAck.Count,FPendingDispatch.Count]);
end;

procedure TMQTTSession.SendPendingReconnectMessages;
var
  I,C: Integer;
  M: TMQTTMessage;
begin
  C := FPendingReconnect.Count;
  if C > 0 then
    begin
      Log.Send(mtDebug,'Sending %d messages queued pending reconnect',[C]);
      for I := C - 1 downto 0 do
        begin
          M := FPendingReconnect[I];
          FPendingReconnect.Delete(I);
          FPendingTransmission.Add(M);
          Assert(Assigned(M));
        end;
      FPendingReconnect.Clear;
    end;
end;

procedure TMQTTSession.SendPendingTransmissionMessages;
var
  I,C: Integer;
  M: TMQTTMessage;
begin
  C := FPendingTransmission.Count;
  if C > 0 then
    begin
      Log.Send(mtDebug,'Sending %d messages pending transmission',[C]);
      for I := 0 to C - 1 do
        begin
          M := FPendingTransmission[I];
          Connection.Publish(M.Topic,M.Data,M.QOS,M.Retain);
        end;
      FPendingTransmission.Clear;
    end;
end;

procedure TMQTTSession.ResendUnacknowledgedMessages;
var { To satisfy REQ: When a client reconnects with CleanSession=0, Retransmit any unacknowledged PUBLISH or PUBREL packets}
  I, C: Integer;
  P: TMQTTPacket;
  PP: TMQTTPUBLISHPacket;
  PR: TMQTTPUBRELPacket;
begin
  Assert(Assigned(FConnection));
  if not Assigned(FConnection) then Exit;
  C := FWaitingForAck.Count;
  for I := C-1 downto 0 do
    begin
      P := FWaitingForAck[I];
      Assert(Assigned(P));
      if Assigned(P) then
        if P.PacketType=ptPUBLISH then
          begin
            PP := TMQTTPublishPacket.Create;
            try
              PP.PacketID  := (P as TMQTTPUBLISHPacket).PacketID;
              PP.Topic     := (P as TMQTTPUBLISHPacket).Topic;
              PP.Data      := (P as TMQTTPUBLISHPacket).Data;
              PP.QOS       := (P as TMQTTPUBLISHPacket).QOS;
              PP.Retain    := (P as TMQTTPUBLISHPacket).Retain;
              PP.Duplicate := True;
              PP.WriteToBuffer(Connection.SendBuffer);
              Log.Send(mtDebug,'Resending PUBLISH (%s)',[PP.AsString]);
              Server.SendData(Connection);
            finally
              PP.Free;
            end;
          end
        else
          if P.PacketType=ptPUBREL then
            begin
              PR := TMQTTPUBRELPacket.Create;
              try
                PR.PacketID := (P as TMQTTPUBRELPacket).PacketID;
                PR.WriteToBuffer(Connection.SendBuffer);
                Log.Send(mtDebug,'Resending PUBREL (%s)',[PR.AsString]);
                Server.SendData(Connection);
              finally
                PR.Free;
              end;
            end;
    end;
end;

procedure TMQTTSession.DispatchMessage(Message: TMQTTMessage);
var
  I: Integer;
  Subscription: TMQTTSubscription;
  QueuedMessage: TMQTTMessage;
begin
  Assert(Message.Retain = False);
  for I := 0 to Subscriptions.Count - 1 do
    begin
      Subscription := Subscriptions[I];
      if CheckTopicMatchesFilter(Message.Tokens,Subscription.Tokens) then
        begin
          Subscription.Age := 0;
          // If this is a QoS0 message
          if Message.QOS = qtAT_MOST_ONCE then
            begin
              // If we are connected, send the message right away
              if Assigned(Connection) and (Connection.State <> csDisconnected) then
                Connection.Publish(Message.Topic,Message.Data,Subscription.QOS,False)
              else
                // Otherwise, we may optionally store the message for delivery when the client reconnects
                if (Server.StoreOfflineQoS0Messages) then
                  begin
                    QueuedMessage := Message.Clone;
                    QueuedMessage.Retain := False;                // Is this necessary? Yes
                    QueuedMessage.QOS := Subscription.QOS;
                    FPendingReconnect.Update(QueuedMessage);
                  end;
            end
          { "It MUST set the RETAIN flag to 0 when a PUBLISH Packet is sent to a
            Client because it matches an established subscription regardless of
            how the flag was set in the message it received" [MQTT-3.3.1-9].

            The only case where the Retain=True in a PUBLISH message sent by
            the server is where a server sends a retained message as a result of
            a new subscription. Retained messages are sent by the
            TMQTTServer.SendRetainedMessages() function, which directly adds
            packets to the PendingTransmission queue and does not use this function. }
          else
            // If this is a QoS1 or QoS2 message, queue the message for transmission
            begin
              // Otherwise queue it to send later
              QueuedMessage        := Message.Clone;
              QueuedMessage.Retain := False;                // Is this necessary? Yes
              QueuedMessage.QOS    := Subscription.QOS;
              if Assigned(Connection) and (Connection.State <> csDisconnected) then
                FPendingTransmission.Add(QueuedMessage)
              else
                FPendingReconnect.Update(QueuedMessage);
            end;
        end;
    end;

end;

procedure TMQTTSession.ProcessAckQueue;
var
  I: Integer;
  Packet: TMQTTQueuedPacket;
begin
  for I := FWaitingForAck.Count - 1 downto 0 do
    begin
      Packet := FWaitingForAck[I];
      if Packet.SecondsInQueue >= Server.ResendPacketTimeout then
        begin
          if Packet.ResendCount < Server.MaxResendAttempts then
            begin
              if Packet.PacketType = ptPUBLISH then
                (Packet as TMQTTPUBLISHPacket).Duplicate := True;
              Packet.WriteToBuffer(Connection.SendBuffer);
              Log.Send(mtWarning,'Resending %s packet',[Packet.PacketTypeName]);
              Server.SendData(Connection);
              Packet.SecondsInQueue := 0;
              Packet.ResendCount := Packet.ResendCount + 1;
            end
          else
            begin
              FWaitingForAck.Delete(I);
              if Packet.PacketType in [ptSUBACK,ptUNSUBACK,ptPUBACK,ptPUBCOMP] then
                FPacketIDManager.ReleaseID(Packet.PacketID);
              Log.Send(mtWarning,'A %s packet went unacknowledged by the client',[Packet.PacketTypeName]);
              Packet.Free;
            end;
        end;
    end;
end;

procedure TMQTTSession.ProcessSessionAges;
var
  I: Integer;
  Sub: TMQTTSubscription;
begin
  // Age each subscription.  If the subscription is older than the maximum subscription age and
  // it is not marked as persistent, then destroy it.
  for I := 0 to Subscriptions.Count - 1 do
    begin
      Sub := Subscriptions[I];
      if Sub.Age < Server.MaxSubscriptionAge then
        Sub.Age := Sub.Age + 1
      else
        if Server.MaxSubscriptionAge > 0 then
          Subscriptions.Delete(I);
    end;
  inc(FAge);
  // If there are no subscriptions remaining and the session is older than the maximum session age then destroy it.
  if (Subscriptions.Count = 0) and (Server.MaxSessionAge > 0) and (FAge > Server.MaxSessionAge) then
    begin
      Server.Sessions.Remove(Self);
      Destroy;
    end;
end;

procedure TMQTTSession.SendRetainedMessages(NewSubscriptions: TMQTTSubscriptionList);
var
  I: Integer;
  Subscription: TMQTTSubscription;
begin
  for I := 0 to NewSubscriptions.Count - 1 do
    begin
      Subscription := NewSubscriptions[I];
      if Subscription.Tokens.Valid then
        Connection.Server.SendRetainedMessages(Self,Subscription);
    end;
  SendPendingTransmissionMessages;
end;

end.

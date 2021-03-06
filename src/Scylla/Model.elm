module Scylla.Model exposing (..)
import Scylla.Api exposing (..)
import Scylla.Sync exposing (SyncResponse, HistoryResponse, JoinedRoom, senderName, roomName, roomJoinedUsers)
import Scylla.Login exposing (LoginResponse, Username, Password)
import Scylla.UserData exposing (UserData)
import Scylla.Route exposing (Route(..), RoomId)
import Scylla.Messages exposing (..)
import Scylla.Storage exposing (..)
import Scylla.Markdown exposing (..)
import Browser.Navigation as Nav
import Browser.Dom exposing (Viewport)
import Url.Builder
import Dict exposing (Dict)
import Time exposing (Posix)
import File exposing (File)
import Json.Decode
import Browser
import Http
import Url exposing (Url)

type alias Model =
    { key : Nav.Key
    , route : Route
    , token : Maybe ApiToken
    , loginUsername : Username
    , loginPassword : Password
    , apiUrl : ApiUrl
    , sync : SyncResponse
    , errors : List String
    , roomText : Dict RoomId String
    , sending : Dict Int (RoomId, SendingMessage)
    , transactionId : Int
    , userData : Dict Username UserData
    , connected : Bool
    , searchText : String
    }

type Msg =
    ChangeApiUrl ApiUrl -- During login screen: the API URL (homeserver)
    | ChangeLoginUsername Username -- During login screen: the username
    | ChangeLoginPassword Password -- During login screen: the password
    | AttemptLogin -- During login screen, login button presed
    | TryUrl Browser.UrlRequest -- User attempts to change URL
    | OpenRoom String -- We try open a room
    | ChangeRoute Route -- URL changes
    | ChangeRoomText String String -- Change to a room's input text
    | SendRoomText String -- Sends a message typed into a given room's input
    | SendRoomTextResponse Int (Result Http.Error String) -- A send message response finished
    | ViewportAfterMessage (Result Browser.Dom.Error Viewport) -- A message has been received, try scroll (maybe)
    | ViewportChangeComplete (Result Browser.Dom.Error ()) -- We're done changing the viewport.
    | ReceiveFirstSyncResponse (Result Http.Error SyncResponse) -- HTTP, Sync has finished
    | ReceiveSyncResponse (Result Http.Error SyncResponse) -- HTTP, Sync has finished
    | ReceiveLoginResponse ApiUrl (Result Http.Error LoginResponse) -- HTTP, Login has finished
    | ReceiveUserData Username (Result Http.Error UserData) -- HTTP, receive user data
    | ReceiveCompletedReadMarker (Result Http.Error ()) -- HTTP, read marker request completed
    | ReceiveCompletedTypingIndicator (Result Http.Error ()) -- HTTP, typing indicator request completed
    | ReceiveStoreData Json.Decode.Value -- We are send back a value on request from localStorage.
    | TypingTick Posix -- Tick for updating the typing status
    | History RoomId -- Load history for a room
    | ReceiveHistoryResponse RoomId (Result Http.Error HistoryResponse) -- HTTP, receive history
    | SendImages RoomId
    | SendFiles RoomId
    | ImagesSelected RoomId File (List File)
    | FilesSelected RoomId File (List File)
    | ImageUploadComplete RoomId File (Result Http.Error String)
    | FileUploadComplete RoomId File (Result Http.Error String)
    | SendImageResponse (Result Http.Error String)
    | SendFileResponse (Result Http.Error String)
    | ReceiveMarkdown MarkdownResponse
    | DismissError Int
    | AttemptReconnect
    | UpdateSearchText String

displayName : Model -> Username -> String
displayName m s = Maybe.withDefault (senderName s) <| Maybe.andThen .displayName <| Dict.get s m.userData

roomDisplayName : Model -> JoinedRoom -> String
roomDisplayName m jr =
    let
        customName = roomName jr
        roomUsers = List.filter ((/=) m.loginUsername) <| roomJoinedUsers jr
        singleUserName = if List.length roomUsers == 1 then List.head roomUsers else Nothing
        singleUserDisplayName = Maybe.andThen
            (\u -> Maybe.andThen .displayName <| Dict.get u m.userData) singleUserName
        firstOption d os = case os of
            [] -> d
            ((Just v)::_) -> v
            (Nothing::xs) -> firstOption d xs
    in
        firstOption "<No Name>"
            [ customName
            , singleUserDisplayName
            , singleUserName
            ]

roomUrl : String -> String
roomUrl s = Url.Builder.absolute [ "room", s ] []

loginUrl : String
loginUrl = Url.Builder.absolute [ "login" ] []

newUsers : Model -> List Username -> List Username
newUsers m lus = List.filter (\u -> not <| Dict.member u m.userData) lus

joinedRooms : Model -> Dict RoomId JoinedRoom
joinedRooms m = Maybe.withDefault Dict.empty <| Maybe.andThen .join <| m.sync.rooms

currentRoom : Model -> Maybe JoinedRoom
currentRoom m =
    Maybe.andThen (\s -> Dict.get s <| joinedRooms m) <| currentRoomId m

currentRoomId : Model -> Maybe RoomId
currentRoomId m = case m.route of
    Room r -> Just r
    _ -> Nothing

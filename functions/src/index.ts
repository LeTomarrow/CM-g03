import {initializeApp} from "firebase-admin/app";

initializeApp();

export {
  createRoom, joinRoom, deleteRoom, startGame, switchRoles,
} from "./rooms";

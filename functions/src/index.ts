import {initializeApp} from "firebase-admin/app";

initializeApp();

export {createRoom, joinRoom, deleteRoom} from "./rooms";
export {plantBomb, claimBomb, resolveBomb} from "./bombs";

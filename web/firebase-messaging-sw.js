importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

// Configuración de tu App de Firebase extraída automáticamente
firebase.initializeApp({
  apiKey: "AIzaSyAH8nE8TaB2c2FXirn-u8NRgiPr9YLaKVE",
  appId: "1:780077026565:web:577c80d46ebde384f53b6c",
  messagingSenderId: "780077026565",
  projectId: "appfinanzas-3a1ca",
  authDomain: "appfinanzas-3a1ca.firebaseapp.com",
  storageBucket: "appfinanzas-3a1ca.firebasestorage.app",
  measurementId: "G-Z8N5Z2LEXL"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log("Mensaje cifrado recibido en segundo plano.", payload);
  // El SDK de FlutterFire manejará mostrar la notificación si contiene un "notification" block
});

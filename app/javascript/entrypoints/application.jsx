import "../styles/application.scss";
import React from "react";
import ReactDOM from "react-dom/client";

import App from "../components/App.jsx";

const container = document.getElementById("react-root");
let children = [];

if (container) {
  children = Array.from(container.children).map((child) =>
    React.createElement("div", {
      dangerouslySetInnerHTML: { __html: child.outerHTML },
    }),
  );

  const root = ReactDOM.createRoot(container);
  root.render(
    <React.StrictMode>
      <App>{children}</App>
    </React.StrictMode>,
  );
}

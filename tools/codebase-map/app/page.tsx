import { DiagramViewer } from "./components/diagram-viewer";
import { loadDiagram } from "../lib/diagram-source.mjs";

export default function Page() {
  const diagram = loadDiagram();
  return <DiagramViewer {...diagram} />;
}

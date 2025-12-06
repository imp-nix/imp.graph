# Unit tests for imp.graph
{ lib }:
let
  visualize = import ../nix { inherit lib; };

  # Sample graph for testing visualization functions
  sampleGraph = {
    nodes = [
      {
        id = "modules.home.shell";
        path = /test/path/shell;
        type = "configTree";
      }
      {
        id = "modules.home.devTools";
        path = /test/path/devTools;
        type = "configTree";
      }
      {
        id = "hosts.workstation";
        path = /test/path/workstation;
        type = "configTree";
      }
    ];
    edges = [
      {
        from = "modules.home.shell";
        to = "hosts.workstation";
        type = "import";
      }
      {
        from = "modules.home.devTools";
        to = "hosts.workstation";
        type = "import";
      }
    ];
  };

  # Minimal graph with single node
  minimalGraph = {
    nodes = [
      {
        id = "single.node";
        path = /test/single;
        type = "file";
      }
    ];
    edges = [ ];
  };

  # Graph with merge strategy
  mergeGraph = {
    nodes = [
      {
        id = "modules.home.base";
        path = /test/base;
        type = "configTree";
        strategy = "merge";
      }
      {
        id = "modules.home.extended";
        path = /test/extended;
        type = "configTree";
        strategy = "override";
      }
    ];
    edges = [
      {
        from = "modules.home.base";
        to = "modules.home.extended";
        type = "merge";
        strategy = "merge";
      }
    ];
  };
in
{
  # toJson tests
  toJson."test returns nodes and edges" = {
    expr = visualize.toJson sampleGraph;
    expected = {
      nodes = [
        {
          id = "modules.home.shell";
          path = "/test/path/shell";
          type = "configTree";
        }
        {
          id = "modules.home.devTools";
          path = "/test/path/devTools";
          type = "configTree";
        }
        {
          id = "hosts.workstation";
          path = "/test/path/workstation";
          type = "configTree";
        }
      ];
      edges = sampleGraph.edges;
    };
  };

  toJson."test converts paths to strings" = {
    expr =
      let
        result = visualize.toJson minimalGraph;
      in
      builtins.isString (builtins.head result.nodes).path;
    expected = true;
  };

  toJson."test preserves edge structure" = {
    expr = (visualize.toJson sampleGraph).edges;
    expected = sampleGraph.edges;
  };

  # toJsonMinimal tests
  toJsonMinimal."test returns only id and type" = {
    expr = visualize.toJsonMinimal minimalGraph;
    expected = {
      nodes = [
        {
          id = "single.node";
          type = "file";
        }
      ];
      edges = [ ];
    };
  };

  toJsonMinimal."test excludes path from nodes" = {
    expr =
      let
        result = visualize.toJsonMinimal sampleGraph;
        firstNode = builtins.head result.nodes;
      in
      firstNode ? path;
    expected = false;
  };

  toJsonMinimal."test preserves strategy when present" = {
    expr =
      let
        result = visualize.toJsonMinimal mergeGraph;
        nodeWithStrategy = builtins.head (lib.filter (n: n.id == "modules.home.base") result.nodes);
      in
      nodeWithStrategy.strategy;
    expected = "merge";
  };

  toJsonMinimal."test excludes strategy when absent" = {
    expr =
      let
        result = visualize.toJsonMinimal sampleGraph;
        firstNode = builtins.head result.nodes;
      in
      firstNode ? strategy;
    expected = false;
  };

  # toWasmData tests
  toWasmData."test produces nodes and links" = {
    expr =
      let
        result = visualize.toWasmData { graph = sampleGraph; };
      in
      builtins.isAttrs result && result ? nodes && result ? links;
    expected = true;
  };

  toWasmData."test nodes have required fields" = {
    expr =
      let
        result = visualize.toWasmData { graph = minimalGraph; };
        node = builtins.head result.nodes;
      in
      node ? id && node ? label && node ? group;
    expected = true;
  };

  toWasmData."test self-referential edges are filtered" = {
    expr =
      let
        selfRefGraph = {
          nodes = [
            {
              id = "modules.self";
              path = /test/self;
              type = "file";
            }
          ];
          edges = [
            {
              from = "modules.self";
              to = "modules.self";
              type = "import";
            }
          ];
        };
        result = visualize.toWasmData { graph = selfRefGraph; };
      in
      lib.length result.links;
    expected = 0;
  };

  # clusterColors tests
  clusterColors."test contains expected cluster keys" = {
    expr = visualize.clusterColors ? "modules.home";
    expected = true;
  };

  clusterColors."test contains nixos modules color" = {
    expr = visualize.clusterColors ? "modules.nixos";
    expected = true;
  };

  clusterColors."test contains outputs color" = {
    expr = visualize.clusterColors ? "outputs.nixosConfigurations";
    expected = true;
  };

  clusterColors."test colors are valid hex strings" = {
    expr =
      let
        homeColor = visualize.clusterColors."modules.home";
      in
      lib.hasPrefix "#" homeColor && builtins.stringLength homeColor == 7;
    expected = true;
  };

  # Edge case tests
  edgeCases."test handles nodes with dots in names" = {
    expr =
      let
        dottedGraph = {
          nodes = [
            {
              id = "a.b.c.d.e";
              path = /test/deep;
              type = "file";
            }
          ];
          edges = [ ];
        };
        result = visualize.toWasmData { graph = dottedGraph; };
      in
      builtins.isAttrs result && result ? nodes;
    expected = true;
  };

  edgeCases."test handles empty graph" = {
    expr =
      let
        emptyGraph = {
          nodes = [ ];
          edges = [ ];
        };
        result = visualize.toWasmData { graph = emptyGraph; };
      in
      result.nodes == [ ] && result.links == [ ];
    expected = true;
  };
}

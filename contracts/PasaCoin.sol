// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Pasanaku {
    struct Participante {
        address wallet;
        uint montoARecibir;
        bool haRecibidoFondos;
        bool esSuTurno;
        bool esBeneficiario; // Indica si el participante ya ha recibido fondos en alguna ronda
    }

    struct Sala {
        address anfitrion;
        uint cantidadParticipantes;
        uint montoAportarPorRonda;
        uint montoTotalARedibirPorRonda;
        uint numeroDeRondas;
        uint rondaActual;
        string tipoDeReparticion; // "ruleta" o "enlistar"
        uint diasParaEnviarAporte;
        uint pozoTotal;
        bool salaActiva; // Indica si la sala está activa o cerrada
        Participante[] participantes;
    }

    mapping(bytes32 => Sala) public salas;

    event SalaCerrada(bytes32 indexed salaId, string mensaje);

    // Crear una sala de Pasanaku
    function crearSala(
        address _anfitrion,
        uint _cantidadParticipantes,
        uint _montoAportarPorRonda,
        string memory _tipoDeReparticion,
        uint _diasParaEnviarAporte
    ) public returns (bytes32) {
        require(_cantidadParticipantes > 1, "Debe haber al menos 2 participantes");
        require(_montoAportarPorRonda > 0, "El monto de la contribucion debe ser mayor a 0");
        require(
            keccak256(abi.encodePacked(_tipoDeReparticion)) == keccak256(abi.encodePacked("ruleta")) ||
            keccak256(abi.encodePacked(_tipoDeReparticion)) == keccak256(abi.encodePacked("enlistar")),
            "Tipo de distribucion invalido"
        );

        bytes32 salaId = keccak256(abi.encodePacked(_anfitrion, block.timestamp));
        Sala storage nuevaSala = salas[salaId];
        nuevaSala.anfitrion = _anfitrion;
        nuevaSala.cantidadParticipantes = _cantidadParticipantes;
        nuevaSala.montoAportarPorRonda = _montoAportarPorRonda;
        nuevaSala.montoTotalARedibirPorRonda = _cantidadParticipantes * _montoAportarPorRonda;
        nuevaSala.numeroDeRondas = _cantidadParticipantes;
        nuevaSala.rondaActual = 1;
        nuevaSala.tipoDeReparticion = _tipoDeReparticion;
        nuevaSala.diasParaEnviarAporte = _diasParaEnviarAporte;
        nuevaSala.salaActiva = true;

        // Añadir al anfitrión como primer participante
        Participante memory anfitrionParticipante;
        anfitrionParticipante.wallet = _anfitrion;
        anfitrionParticipante.montoARecibir = nuevaSala.montoTotalARedibirPorRonda;
        anfitrionParticipante.haRecibidoFondos = false;
        anfitrionParticipante.esSuTurno = false;
        anfitrionParticipante.esBeneficiario = false;

        nuevaSala.participantes.push(anfitrionParticipante);

        return salaId;
    }

    // Unirse a una sala de Pasanaku
    function unirseASala(bytes32 salaId, address participanteDireccion) public {
        Sala storage sala = salas[salaId];
        require(sala.anfitrion != address(0), "La sala no existe");
        require(sala.participantes.length < sala.cantidadParticipantes, "La sala esta llena");
        require(sala.salaActiva, "La sala esta cerrada");

        // Verifica si la dirección ya está en uso
        for (uint i = 0; i < sala.participantes.length; i++) {
            require(sala.participantes[i].wallet != participanteDireccion, "Este participante ya esta en la sala");
        }

        Participante memory nuevoParticipante;
        nuevoParticipante.wallet = participanteDireccion;
        nuevoParticipante.montoARecibir = sala.montoTotalARedibirPorRonda;
        nuevoParticipante.haRecibidoFondos = false;
        nuevoParticipante.esSuTurno = false;
        nuevoParticipante.esBeneficiario = false;

        sala.participantes.push(nuevoParticipante);
    }

    // Contribuir con el aporte
    function contribuir(bytes32 salaId, address participanteDireccion, uint monto) public payable {
        Sala storage sala = salas[salaId];
        require(sala.salaActiva, "La sala esta cerrada");
        require(sala.participantes.length == sala.cantidadParticipantes, "No todos los participantes se han unido aun");
        require(monto == sala.montoAportarPorRonda, "El monto aportado es incorrecto");
        require(sala.rondaActual <= sala.numeroDeRondas, "Todas las rondas han finalizado");

        // Verifica si es participante
        bool esParticipante = false;
        for (uint i = 0; i < sala.participantes.length; i++) {
            if (sala.participantes[i].wallet == participanteDireccion) {
                esParticipante = true;
                break;
            }
        }
        require(esParticipante, "No eres participante de esta sala");

        sala.pozoTotal += monto;
    }

    // Realizar sorteo para tipo de repartición "ruleta"
    function realizarSorteoRuleta(bytes32 salaId) public {
        Sala storage sala = salas[salaId];
        require(sala.salaActiva, "La sala esta cerrada");
        require(sala.pozoTotal >= sala.montoTotalARedibirPorRonda, "No se ha alcanzado el monto total");
        require(keccak256(abi.encodePacked(sala.tipoDeReparticion)) == keccak256(abi.encodePacked("ruleta")), "Tipo de reparticion no es ruleta");

        // Lista de participantes que aún no han sido beneficiarios
        address[] memory posiblesBeneficiarios = new address[](sala.participantes.length);
        uint contador = 0;

        for (uint i = 0; i < sala.participantes.length; i++) {
            if (!sala.participantes[i].esBeneficiario) {
                posiblesBeneficiarios[contador] = sala.participantes[i].wallet;
                contador++;
            }
        }

        require(contador > 0, "No hay participantes disponibles para el sorteo");

        uint indiceAleatorio = uint(keccak256(abi.encodePacked(block.timestamp, block.difficulty))) % contador;
        address ganador = posiblesBeneficiarios[indiceAleatorio];

        // Marcar al ganador como beneficiario
        for (uint i = 0; i < sala.participantes.length; i++) {
            if (sala.participantes[i].wallet == ganador) {
                sala.participantes[i].esBeneficiario = true;
                sala.participantes[i].haRecibidoFondos = true;
                sala.participantes[i].esSuTurno = false;
                break;
            }
        }

        payable(ganador).transfer(sala.pozoTotal);
        sala.pozoTotal = 0;

        // Avanza a la siguiente ronda o cierra la sala si es la última ronda
        if (sala.rondaActual == sala.numeroDeRondas) {
            sala.salaActiva = false;
            emit SalaCerrada(salaId, "El juego ha terminado. La sala ha sido cerrada.");
        } else {
            sala.rondaActual++;
        }
    }

    // Obtener detalles de una sala, incluyendo la cantidad de participantes inscritos actualmente
    function obtenerDetallesSala(bytes32 salaId) public view returns (
        address, 
        uint, 
        uint, 
        uint, 
        uint, 
        string memory, 
        uint, 
        uint,  
        bool  
    ) {
        Sala storage sala = salas[salaId];
        return (
            sala.anfitrion,
            sala.cantidadParticipantes,
            sala.montoAportarPorRonda,
            sala.montoTotalARedibirPorRonda,
            sala.rondaActual,
            sala.tipoDeReparticion,
            sala.diasParaEnviarAporte,
            sala.participantes.length,
            sala.salaActiva  
        );
    }

    // Buscar una sala por su ID y obtener información básica
    function buscarSala(bytes32 salaId) public view returns (
        uint, 
        uint, 
        uint
    ) {
        Sala storage sala = salas[salaId];
        require(sala.anfitrion != address(0), "La sala no existe");

        return (
            sala.montoAportarPorRonda,         
            sala.cantidadParticipantes,        
            sala.participantes.length          
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Pasanaku {
    struct Participante {
        address wallet;
        uint montoARecibir;
        bool haRecibidoFondos;
        bool esSuTurno;
        bool esBeneficiario;  // Nuevo campo para indicar si ya fue beneficiario
    }

    struct Sala {
        address anfitrion;
        uint cantidadParticipantes;
        uint montoAportarPorRonda;
        uint montoTotalARedibirPorRonda;
        uint numeroDeRondas;
        uint rondaActual;
        string tipoDeReparticion;
        uint diasParaEnviarAporte;
        uint pozoTotal;
        bool salaActiva;
        Participante[] participantes;
    }

    mapping(bytes32 => Sala) public salas;

    event SalaCerrada(bytes32 indexed salaId, string mensaje);
    event BeneficiarioSeleccionado(bytes32 indexed salaId, address beneficiario);

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

    // Realizar sorteo para seleccionar al beneficiario (solo anfitrion)
    function realizarSorteo(bytes32 salaId, address anfitrionDireccion) public {
        Sala storage sala = salas[salaId];
        require(sala.anfitrion == anfitrionDireccion, "Solo el anfitrion puede realizar el sorteo");
        require(sala.pozoTotal >= sala.montoTotalARedibirPorRonda, "No se ha alcanzado el monto total");

        uint indiceAleatorio;
        address beneficiario;

        do {
            indiceAleatorio = uint(keccak256(abi.encodePacked(block.timestamp, block.difficulty))) % sala.participantes.length;
            beneficiario = sala.participantes[indiceAleatorio].wallet;
        } while (sala.participantes[indiceAleatorio].esBeneficiario);

        sala.participantes[indiceAleatorio].esBeneficiario = true;
        sala.participantes[indiceAleatorio].esSuTurno = true;

        emit BeneficiarioSeleccionado(salaId, beneficiario);
    }

    // Enviar el monto total al beneficiario
    function enviarMontoTotal(bytes32 salaId) public {
        Sala storage sala = salas[salaId];
        require(sala.pozoTotal >= sala.montoTotalARedibirPorRonda, "No se ha alcanzado el monto total");

        address payable destinatario;
        for (uint i = 0; i < sala.participantes.length; i++) {
            if (sala.participantes[i].esSuTurno && !sala.participantes[i].haRecibidoFondos) {
                destinatario = payable(sala.participantes[i].wallet);
                sala.participantes[i].haRecibidoFondos = true;
                sala.participantes[i].esSuTurno = false;
                break;
            }
        }

        destinatario.transfer(sala.pozoTotal);
        sala.pozoTotal = 0;

        bool todosBeneficiarios = true;
        for (uint i = 0; i < sala.participantes.length; i++) {
            if (!sala.participantes[i].esBeneficiario) {
                todosBeneficiarios = false;
                break;
            }
        }

        if (todosBeneficiarios || sala.rondaActual == sala.numeroDeRondas) {
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
